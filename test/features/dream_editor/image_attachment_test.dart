import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_calendar/data/drift_calendar_repository.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';
import 'package:morpheus/features/dream_editor/data/image_attachment_service.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:morpheus/features/dream_statistics/data/drift_statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';
import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';

const image = DreamImage(
  fileName: 'artificial_test.img',
  width: 120,
  height: 80,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真实 v2 升级当前版本保留原文反馈和时间；附件关闭重开后恢复，正文更新不删图片', () async {
    final dir = await Directory.systemTemp.createTemp(
      'morpheus_image_upgrade_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/upgrade.sqlite');
    var db = AppDatabase(
      NativeDatabase(
        file,
        setup: (old) {
          old.execute(
            'CREATE TABLE dream_records (dream_date TEXT NOT NULL PRIMARY KEY, content TEXT NOT NULL, created_at_millis INTEGER NOT NULL, updated_at_millis INTEGER NOT NULL, dream_mood TEXT, sleep_score INTEGER CHECK (sleep_score BETWEEN 1 AND 5), sleep_factors TEXT, flow_completed INTEGER NOT NULL DEFAULT 0)',
          );
          old.execute('PRAGMA user_version = 2');
          old.execute(
            "INSERT INTO dream_records VALUES ('2026-11-12', '  人工原文\n🌙  ', 123456, 234567, 'good', 4, '[\"stress\"]', 1)",
          );
        },
      ),
    );
    final date = DateTime(2026, 11, 12);
    try {
      final repo = DriftDreamRepository(db);
      final old = (await repo.getByDate(date))!;
      expect(old.content, '  人工原文\n🌙  ');
      expect(old.createdAt.millisecondsSinceEpoch, 123456);
      expect(old.updatedAt.millisecondsSinceEpoch, 234567);
      expect(old.feedback.mood, DreamMood.good);
      expect(old.feedback.sleepScore, 4);
      expect(old.feedback.factors, {SleepFactor.stress});
      expect(old.feedback.completed, isTrue);
      expect(old.images, isEmpty);
      await repo.save(date: date, content: old.content, images: [image]);
    } finally {
      await db.close();
    }
    db = AppDatabase(NativeDatabase(file));
    try {
      final repo = DriftDreamRepository(db);
      expect(
        (await repo.getByDate(date))!.images.single.fileName,
        image.fileName,
      );
      await repo.save(date: date, content: '');
      final updated = (await repo.getByDate(date))!;
      expect(updated.images.single.aspectRatio, 1.5);
      expect(updated.feedback.sleepScore, 4);
      expect(updated.createdAt.millisecondsSinceEpoch, 123456);
      await repo.save(date: date, content: '', images: []);
      expect((await repo.getByDate(date))!.images, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('只有图片进入历史月历和统计，一天多张只算一次，不推断反馈', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftDreamRepository(db);
    final date = DateTime(2026, 11, 12);
    await repo.save(
      date: date,
      content: ' \n',
      images: [
        image,
        const DreamImage(fileName: 'second.img', width: 80, height: 120),
      ],
    );
    expect((await repo.getAll()).single.hasData, isTrue);
    expect(
      await DriftCalendarRepository(db).watchRecordedDatesInMonth(date).first,
      {'2026-11-12'},
    );
    final window = StatisticsWindow(StatisticsPeriod.month, date);
    final stats = DriftStatisticsRepository(db);
    expect(await stats.watchRecordedDates(window).first, {'2026-11-12'});
    final feedback = SleepFeedbackStatistics(
      window: window,
      records: await stats.watchRecords(window).first,
      today: date,
    );
    expect(feedback.averageScore, isNull);
    expect(feedback.goodCount, 0);
    expect(feedback.topFactors, isEmpty);
    await repo.save(date: date, content: '清空后仍保留图');
    await repo.save(date: date, content: '');
    expect((await repo.getAll()).single.images, hasLength(2));
    await repo.deleteByDate(date);
    expect(await stats.watchRecordedDates(window).first, isEmpty);
  });

  test('损坏图片元数据不能作为空记录继续保存，拒绝目录穿越文件名', () async {
    expect(
      () => DreamImage.decode(
        '[{"fileName":"../private.img","width":1,"height":1}]',
      ),
      throwsFormatException,
    );
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftDreamRepository(db);
    await repo.save(date: DateTime.now(), content: '', images: [image]);
    await db.customStatement("UPDATE dream_records SET images = 'broken'");
    await expectLater(repo.getAll(), throwsFormatException);
    await expectLater(
      repo.save(date: DateTime.now(), content: '误写'),
      throwsFormatException,
    );
  });

  test('原图复制到持久目录，删除相册临时文件及新建服务后仍存在', () async {
    final dir = await Directory.systemTemp.createTemp('morpheus_image_copy_');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/picker.png');
    await source.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
      ),
    );
    final service = LocalImageAttachmentService(
      directory: () async => Directory('${dir.path}/support'),
    );
    final attachment = await service.importFile(XFile(source.path));
    final bytes = await source.readAsBytes();
    await source.delete();
    final reopened = LocalImageAttachmentService(
      directory: () async => Directory('${dir.path}/support'),
    );
    expect(await (await reopened.fileFor(attachment)).readAsBytes(), bytes);
    expect(attachment.width, 1);
    await reopened.removeFiles([attachment]);
    expect(await (await reopened.fileFor(attachment)).exists(), isFalse);
  });

  test('Android lost-data 恢复保留选图日期，日志在确认前可重复恢复', () async {
    final dir = await Directory.systemTemp.createTemp('morpheus_android_lost_');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/source.png');
    await source.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
      ),
    );
    final picker = _LostPicker(XFile(source.path));
    final images = Directory('${dir.path}/dream_images');
    await images.create();
    await File(
      '${images.path}/pending.json',
    ).writeAsString('{"date":"2026-10-31","images":[]}');
    final service = LocalImageAttachmentService(
      picker: picker,
      directory: () async => dir,
      isAndroid: true,
    );
    final recovered = (await service.recover())!;
    expect(recovered.date, DateTime(2026, 10, 31));
    expect(recovered.images, hasLength(1));
    picker.response = LostDataResponse.empty();
    final again = (await service.recover())!;
    expect(again.images.single.fileName, recovered.images.single.fileName);
    await service.completeSelection(recovered.date);
    expect(await service.recover(), isNull);
  });

  test('启动恢复读完瞬间通知切日也等待，恢复图不会合入通知的新日期', () async {
    final repo = ImageTestRepository();
    final date = DateTime.now().subtract(const Duration(days: 2));
    await repo.save(date: date, content: '恢复日期人工正文');
    final service = ImageTestService()
      ..pending = PendingImageSelection(DreamEntry.dateOnly(date), [image]);
    final container = ProviderContainer(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repo),
        imageAttachmentServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    Future<bool>? navigation;
    container.listen(dreamEditorControllerProvider, (previous, next) {
      if (previous?.isLoading == true &&
          !next.isLoading &&
          navigation == null) {
        navigation = container
            .read(dreamEditorControllerProvider.notifier)
            .selectDate(DateTime.now());
      }
    });
    await spin();
    expect(navigation, isNotNull);
    expect(await navigation, isTrue);
    expect(
      (await repo.getByDate(date))!.images.single.fileName,
      image.fileName,
    );
    expect((await repo.getByDate(date))!.content, '恢复日期人工正文');
    expect(container.read(dreamEditorControllerProvider).images, isEmpty);
  });

  group('附件与自动保存队列', () {
    late ImageTestRepository repo;
    late ImageTestService service;
    late ProviderContainer container;
    late DreamEditorController controller;
    setUp(() async {
      repo = ImageTestRepository();
      service = ImageTestService();
      container = ProviderContainer(
        overrides: [
          dreamRepositoryProvider.overrideWithValue(repo),
          imageAttachmentServiceProvider.overrideWithValue(service),
        ],
      );
      controller = container.read(dreamEditorControllerProvider.notifier);
      await spin();
    });
    tearDown(() => container.dispose());

    test('取消或导入失败保留文字、不添加附件', () async {
      controller.contentChanged('人工文字');
      service.result = [];
      await controller.addImage();
      expect(container.read(dreamEditorControllerProvider).content, '人工文字');
      service.fail = true;
      await controller.addImage();
      expect(
        container.read(dreamEditorControllerProvider).attachmentError,
        isNotNull,
      );
      expect(container.read(dreamEditorControllerProvider).images, isEmpty);
    });

    test('读取失败禁止打开相册，重试只重新读取原记录', () async {
      repo.readFails = true;
      await controller.selectDate(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      await controller.addImage();
      expect(service.picks, 0);
      expect(
        container.read(dreamEditorControllerProvider).failure,
        DreamEditorFailure.load,
      );
      repo.readFails = false;
      await controller.retryLastOperation();
      expect(container.read(dreamEditorControllerProvider).canEdit, isTrue);
    });

    test('恢复日志确认失败保留失败状态并锁住删除，重试成功后才能移除', () async {
      service.ackFails = true;
      await controller.addImage();
      expect(
        container.read(dreamEditorControllerProvider).failure,
        DreamEditorFailure.save,
      );
      controller.removeImage(image);
      expect(
        container.read(dreamEditorControllerProvider).images,
        hasLength(1),
      );
      expect((await repo.getByDate(DateTime.now()))!.images, hasLength(1));
      service.ackFails = false;
      await controller.retryLastOperation();
      controller.removeImage(image);
      service.cleanupFails = true;
      await controller.flushPendingSave();
      expect(await repo.getByDate(DateTime.now()), isNull);
      expect(
        container.read(dreamEditorControllerProvider).saveStatus,
        DreamSaveStatus.saved,
      );
    });

    test('选图期间切日等待，返回的图片只附到原日期，重复点击只打开一次', () async {
      final oldDate = container.read(dreamEditorControllerProvider).date;
      service.gate = Completer<List<DreamImage>>();
      final adding = controller.addImage();
      await spin();
      await controller.addImage();
      final selecting = controller.selectDate(
        oldDate.subtract(const Duration(days: 1)),
      );
      await spin();
      expect(container.read(dreamEditorControllerProvider).date, oldDate);
      expect(service.picks, 1);
      service.gate!.complete([image]);
      await adding;
      expect(await selecting, isTrue);
      expect(
        (await repo.getByDate(oldDate))!.images.single.fileName,
        image.fileName,
      );
      expect(container.read(dreamEditorControllerProvider).images, isEmpty);
    });

    test('保存失败保留图草稿，重试成功才确认恢复日志；删除失败不提前删文件', () async {
      repo.fail = true;
      await controller.addImage();
      expect(
        container.read(dreamEditorControllerProvider).failure,
        DreamEditorFailure.save,
      );
      expect(
        container.read(dreamEditorControllerProvider).images,
        hasLength(1),
      );
      expect(service.completed, 0);
      repo.fail = false;
      await controller.retryLastOperation();
      expect(service.completed, 1);
      expect(
        container.read(dreamEditorControllerProvider).saveStatus,
        DreamSaveStatus.saved,
      );
      repo.fail = true;
      controller.removeImage(image);
      await controller.saveNow();
      expect(service.removed, isEmpty);
      expect((await repo.getByDate(DateTime.now()))!.images, hasLength(1));
      repo.fail = false;
      await controller.retryLastOperation();
      expect(await repo.getByDate(DateTime.now()), isNull);
      expect(service.removed.single.fileName, image.fileName);
    });

    test('清空正文仍保留图；删最后图片时反馈和完成标记不受损', () async {
      await controller.addImage();
      controller.contentChanged('');
      await controller.saveNow();
      expect((await repo.getByDate(DateTime.now()))!.images, hasLength(1));
      controller.feedbackChanged(
        const DailyFeedback(sleepScore: 5, completed: true),
      );
      controller.removeImage(image);
      await controller.flushPendingSave();
      final record = (await repo.getByDate(DateTime.now()))!;
      expect(record.images, isEmpty);
      expect(record.feedback.sleepScore, 5);
      expect(record.feedback.completed, isTrue);
    });

    test('文字旧快照写入中选图返回，不提前删除恢复日志；最终快照包含图', () async {
      service.gate = Completer<List<DreamImage>>();
      final adding = controller.addImage();
      await spin();
      repo.gate = Completer<void>();
      controller.contentChanged('第一版人工文字');
      final saving = controller.saveNow();
      await spin();
      service.gate!.complete([image]);
      await spin();
      final nextGate = Completer<void>();
      repo.nextGate = nextGate;
      repo.gate!.complete();
      await spin();
      expect(service.completed, 0);
      controller.contentChanged('最新人工文字');
      nextGate.complete();
      await saving;
      await adding;
      final result = (await repo.getByDate(DateTime.now()))!;
      expect(result.content, '最新人工文字');
      expect(result.images.single.fileName, image.fileName);
      expect(service.completed, 1);
      expect(repo.maxWrites, 1);
    });
  });
}

Future<void> spin() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class ImageTestService implements IImageAttachmentService {
  PendingImageSelection? pending;
  List<DreamImage> result = [image];
  Completer<List<DreamImage>>? gate;
  bool fail = false;
  bool ackFails = false;
  bool cleanupFails = false;
  int picks = 0;
  int completed = 0;
  List<DreamImage> removed = [];
  @override
  Future<List<DreamImage>> pick(DateTime date) async {
    picks++;
    if (fail) throw StateError('人工导入错误');
    return gate?.future ?? result;
  }

  @override
  Future<PendingImageSelection?> recover() async => pending;
  @override
  Future<void> completeSelection(DateTime date) async {
    if (ackFails) throw StateError('人工日志确认故障');
    completed++;
  }

  @override
  Future<File> fileFor(DreamImage image) async =>
      File('/tmp/morpheus-nonexistent-test-image');
  @override
  Future<void> removeFiles(Iterable<DreamImage> images) async {
    if (cleanupFails) throw StateError('人工清理故障');
    removed.addAll(images);
  }
}

class _LostPicker extends ImagePicker {
  _LostPicker(XFile file) : response = LostDataResponse(files: [file]);
  LostDataResponse response;
  @override
  Future<LostDataResponse> retrieveLostData() async => response;
}

class ImageTestRepository extends InMemoryDreamRepository {
  bool readFails = false;
  @override
  Future<DreamEntry?> getByDate(DateTime date) async {
    if (readFails) throw StateError('人工读取故障');
    return super.getByDate(date);
  }

  bool fail = false;
  Completer<void>? gate;
  Completer<void>? nextGate;
  int activeWrites = 0;
  int maxWrites = 0;
  Future<void> _before() async {
    if (fail) throw StateError('人工写入故障');
    activeWrites++;
    if (activeWrites > maxWrites) maxWrites = activeWrites;
    final wait = gate;
    if (wait != null) {
      await wait.future;
      gate = nextGate;
      nextGate = null;
    }
    activeWrites--;
  }

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
    DailyFeedback? feedback,
    List<DreamImage>? images,
    List<DreamLink>? links,
  }) async {
    await _before();
    return super.save(
      date: date,
      content: content,
      feedback: feedback,
      images: images,
      links: links,
    );
  }

  @override
  Future<void> deleteByDate(DateTime date) async {
    await _before();
    return super.deleteByDate(date);
  }
}
