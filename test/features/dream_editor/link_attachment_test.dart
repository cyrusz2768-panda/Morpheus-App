import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_calendar/data/drift_calendar_repository.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';
import 'package:morpheus/features/dream_editor/data/link_opener.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_editor/domain/content_web_link.dart';
import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:morpheus/features/dream_statistics/data/drift_statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';
import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';
import 'image_attachment_test.dart' show ImageTestRepository, spin;

const sampleWeb = DreamLink(
  id: 'web_test',
  url: 'https://example.com/dream?q=1#night',
  title: '人工网页',
  kind: DreamLinkKind.web,
);
const sampleMusic = DreamLink(
  id: 'music_test',
  url: 'https://music.163.com/#/song?id=123',
  kind: DreamLinkKind.music,
);

void main() {
  test('URL保留查询与音乐fragment，标题可选，www补https，无效URL不执行', () {
    final link = DreamLink.create(
      url: '  https://music.163.com/#/song?id=123  ',
      kind: DreamLinkKind.music,
      title: '   ',
    );
    expect(link.url, sampleMusic.url);
    expect(link.title, isNull);
    expect(
      DreamLink.parseUrl('www.example.com/a')?.toString(),
      'https://www.example.com/a',
    );
    for (final invalid in [
      '',
      'https://',
      'javascript:alert(1)',
      'file:///tmp/a',
      'data:text/html,a',
      'spotify:track:123',
      'https://user:password@example.com',
      'https://example.com/with space',
      '分享歌曲 https://example.com',
      'https://example.com/\nnew',
    ]) {
      expect(DreamLink.parseUrl(invalid), isNull, reason: invalid);
    }
    final decoded = DreamLink.decode(
      DreamLink.encode([sampleWeb, sampleMusic]),
    );
    expect(decoded.map((e) => e.kind), [
      DreamLinkKind.web,
      DreamLinkKind.music,
    ]);
    expect(decoded.last.url, sampleMusic.url);
    expect(
      () => DreamLink.decode(DreamLink.encode([sampleWeb, sampleWeb])),
      throwsFormatException,
    );
  });

  test('真实v3文件无损升级v4，文字反馈图片时间不变，链接增改后关闭重开恢复', () async {
    final dir = await Directory.systemTemp.createTemp('morpheus_link_upgrade_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/upgrade.sqlite');
    var db = AppDatabase(
      NativeDatabase(
        file,
        setup: (old) {
          old.execute(
            'CREATE TABLE dream_records (dream_date TEXT NOT NULL PRIMARY KEY, content TEXT NOT NULL, created_at_millis INTEGER NOT NULL, updated_at_millis INTEGER NOT NULL, dream_mood TEXT, sleep_score INTEGER CHECK (sleep_score BETWEEN 1 AND 5), sleep_factors TEXT, flow_completed INTEGER NOT NULL DEFAULT 0, images TEXT NOT NULL DEFAULT \'[]\')',
          );
          old.execute('PRAGMA user_version = 3');
          old.execute(
            'INSERT INTO dream_records VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              '2026-11-12',
              '  人工旧正文\n🌙  ',
              123456,
              234567,
              'good',
              4,
              '["stress"]',
              1,
              '[{"fileName":"preserved.img","width":120,"height":80}]',
            ],
          );
        },
      ),
    );
    final date = DateTime(2026, 11, 12);
    try {
      final repo = DriftDreamRepository(db);
      final old = (await repo.getByDate(date))!;
      expect(old.content, '  人工旧正文\n🌙  ');
      expect(old.createdAt.millisecondsSinceEpoch, 123456);
      expect(old.updatedAt.millisecondsSinceEpoch, 234567);
      expect(old.feedback.mood, DreamMood.good);
      expect(old.feedback.sleepScore, 4);
      expect(old.feedback.factors, {SleepFactor.stress});
      expect(old.feedback.completed, isTrue);
      expect(old.images.single.fileName, 'preserved.img');
      expect(old.links, isEmpty);
      await repo.save(
        date: date,
        content: old.content,
        links: [sampleWeb, sampleMusic],
      );
      await repo.save(
        date: date,
        content: old.content,
        links: [
          sampleWeb,
          DreamLink.create(
            id: sampleMusic.id,
            url: 'https://open.spotify.com/track/artificial',
            title: '人工修改标题',
            kind: DreamLinkKind.music,
          ),
        ],
      );
      // 老调用只写正文，不能清掉新增加的链接或图片。
      await repo.save(date: date, content: '人工新正文');
    } finally {
      await db.close();
    }
    db = AppDatabase(NativeDatabase(file));
    try {
      final entry = (await DriftDreamRepository(db).getByDate(date))!;
      expect(entry.content, '人工新正文');
      expect(entry.createdAt.millisecondsSinceEpoch, 123456);
      expect(entry.feedback.sleepScore, 4);
      expect(entry.feedback.completed, isTrue);
      expect(entry.images.single.aspectRatio, 1.5);
      expect(entry.links, hasLength(2));
      expect(entry.links.last.id, sampleMusic.id);
      expect(entry.links.last.title, '人工修改标题');
      await DriftDreamRepository(db).save(date: date, content: '', links: []);
      expect(
        (await DriftDreamRepository(db).getByDate(date))!.images,
        hasLength(1),
      );
    } finally {
      await db.close();
    }
  });

  test('仅链接也进入历史月历和活动统计，同日多链接算一次且不推断反馈', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftDreamRepository(db);
    final date = DateTime(2026, 11, 12);
    await repo.save(date: date, content: '', links: [sampleWeb, sampleMusic]);
    expect((await repo.getAll()).single.links, hasLength(2));
    expect(
      await DriftCalendarRepository(db).watchRecordedDatesInMonth(date).first,
      {'2026-11-12'},
    );
    final window = StatisticsWindow(StatisticsPeriod.month, date);
    final statistics = DriftStatisticsRepository(db);
    expect(await statistics.watchRecordedDates(window).first, {'2026-11-12'});
    final summary = SleepFeedbackStatistics(
      window: window,
      records: await statistics.watchRecords(window).first,
      today: date,
    );
    expect(summary.averageScore, isNull);
    expect(summary.goodCount, 0);
    expect(summary.topFactors, isEmpty);
    await repo.save(date: date, content: '人工文字');
    await repo.save(date: date, content: '');
    expect((await repo.getByDate(date))!.links, hasLength(2));
    await db.customStatement("UPDATE dream_records SET links = 'broken'");
    await expectLater(repo.getByDate(date), throwsFormatException);
    await expectLater(
      repo.save(date: date, content: '不能覆盖'),
      throwsFormatException,
    );
  });

  group('链接完整草稿与日期保护', () {
    late ImageTestRepository repo;
    late LinkTestOpener opener;
    late ProviderContainer container;
    late DreamEditorController controller;
    DreamEditorState state() => container.read(dreamEditorControllerProvider);
    bool put({
      String? id,
      String url = 'https://example.com',
      String? title,
      DreamLinkKind kind = DreamLinkKind.web,
    }) => controller.putLink(
      date: state().date,
      loadRevision: controller.dateRevision,
      id: id,
      url: url,
      title: title,
      kind: kind,
    );
    void remove(String id) => controller.removeLink(
      date: state().date,
      loadRevision: controller.dateRevision,
      id: id,
    );
    setUp(() async {
      repo = ImageTestRepository();
      opener = LinkTestOpener();
      container = ProviderContainer(
        overrides: [
          dreamRepositoryProvider.overrideWithValue(repo),
          linkOpenerProvider.overrideWithValue(opener),
        ],
      );
      controller = container.read(dreamEditorControllerProvider.notifier);
      await spin();
    });
    tearDown(() => container.dispose());

    test('正文链接打开先保存原文，不额外生成附件，切回仍保留省略协议的原文', () async {
      const content = '🌙 看看example.com/a?q=1#night，人工测试';
      controller.contentChanged(content);
      final match = ContentWebLinks.find(content).single;
      final date = state().date;
      expect(
        await controller.openContentLink(
          date: date,
          loadRevision: controller.dateRevision,
          match: match,
        ),
        isTrue,
      );
      expect(opener.opened.single.url, 'https://example.com/a?q=1#night');
      expect(opener.opened.single.kind, DreamLinkKind.web);
      expect((await repo.getByDate(date))!.content, content);
      expect((await repo.getByDate(date))!.links, isEmpty);
      final revision = controller.dateRevision;
      await controller.selectDate(date.subtract(const Duration(days: 1)));
      await controller.selectDate(date);
      expect(state().content, content);
      expect(
        await controller.openContentLink(
          date: date,
          loadRevision: revision,
          match: match,
        ),
        isFalse,
      );
      expect(opener.opened, hasLength(1));
    });

    test('正文链接保存失败保留草稿，修改后旧链接不打开，无效文字不弹附件错误', () async {
      controller.contentChanged('example.com');
      final match = ContentWebLinks.find(state().content).single;
      repo.fail = true;
      expect(
        await controller.openContentLink(
          date: state().date,
          loadRevision: controller.dateRevision,
          match: match,
        ),
        isFalse,
      );
      expect(opener.opened, isEmpty);
      expect(state().content, 'example.com');
      repo.fail = false;
      controller.contentChanged('无效 example..com');
      await controller.retryLastOperation();
      expect(
        await controller.openContentLink(
          date: state().date,
          loadRevision: controller.dateRevision,
          match: match,
        ),
        isFalse,
      );
      expect(state().attachmentError, isNull);
      expect(opener.opened, isEmpty);
    });

    test('等待保存期间正文链接被修改，旧目标不能打开', () async {
      controller.contentChanged('example.com');
      final match = ContentWebLinks.find(state().content).single;
      repo.gate = Completer<void>();
      final opening = controller.openContentLink(
        date: state().date,
        loadRevision: controller.dateRevision,
        match: match,
      );
      await spin();
      controller.contentChanged('example.org');
      repo.gate!.complete();
      expect(await opening, isFalse);
      expect(opener.opened, isEmpty);
      expect((await repo.getByDate(state().date))!.content, 'example.org');
    });

    test('新增修改删除与正文串行保存，写入期间修改链接最终保存最新快照', () async {
      put(title: '第一版');
      final id = state().links.single.id;
      repo.gate = Completer<void>();
      final saving = controller.saveNow();
      await spin();
      put(id: id, url: 'https://example.com/new#part', title: '最新标题');
      controller.contentChanged('最新人工正文');
      repo.gate!.complete();
      await saving;
      final result = (await repo.getByDate(state().date))!;
      expect(result.content, '最新人工正文');
      expect(result.links.single.title, '最新标题');
      expect(result.links.single.url, 'https://example.com/new#part');
      expect(repo.maxWrites, 1);
      put(id: id, title: '');
      expect(state().links.single.title, isNull);
      remove(id);
      await controller.flushPendingSave();
      expect((await repo.getByDate(state().date))!.links, isEmpty);
      expect((await repo.getByDate(state().date))!.content, '最新人工正文');
    });

    test('保存失败保留链接草稿，重试不重新读取，失败时不打开外部软件', () async {
      put(kind: DreamLinkKind.music);
      repo.fail = true;
      expect(
        await controller.openLink(
          date: state().date,
          loadRevision: controller.dateRevision,
          link: state().links.single,
        ),
        isFalse,
      );
      expect(opener.opened, isEmpty);
      expect(state().failure, DreamEditorFailure.save);
      expect(state().links, hasLength(1));
      repo.fail = false;
      await controller.retryLastOperation();
      final current = state().links.single;
      expect(
        await controller.openLink(
          date: state().date,
          loadRevision: controller.dateRevision,
          link: current,
        ),
        isTrue,
      );
      expect((await repo.getByDate(state().date))!.links.single.id, current.id);
      expect(opener.opened.single.id, current.id);
    });

    test('切日再切回仍拒绝旧表单，旧删除和打开也不影响当前日期', () async {
      put();
      final date = state().date;
      final revision = controller.dateRevision;
      final link = state().links.single;
      await controller.selectDate(date.subtract(const Duration(days: 1)));
      await controller.selectDate(date);
      expect(
        controller.putLink(
          date: date,
          loadRevision: revision,
          id: link.id,
          url: 'https://example.com/old-form',
          kind: DreamLinkKind.web,
        ),
        isFalse,
      );
      controller.removeLink(date: date, loadRevision: revision, id: link.id);
      expect(
        await controller.openLink(
          date: date,
          loadRevision: revision,
          link: link,
        ),
        isFalse,
      );
      expect(state().links.single.url, link.url);
      expect(opener.opened, isEmpty);
    });

    test('读取失败禁止新增修改删除；恢复后仅最后链接删除才删除全空行', () async {
      repo.readFails = true;
      final date = state().date.subtract(const Duration(days: 1));
      await controller.selectDate(date);
      expect(put(), isFalse);
      remove('missing');
      expect(state().links, isEmpty);
      repo.readFails = false;
      await controller.retryLastOperation();
      put();
      await controller.flushPendingSave();
      remove(state().links.single.id);
      await controller.flushPendingSave();
      expect(await repo.getByDate(date), isNull);
    });

    test('清空文字和图片不删链接，删最后链接仍保留评分与完成标记', () async {
      final date = state().date.subtract(const Duration(days: 2));
      await repo.save(
        date: date,
        content: '人工待清文字',
        images: [
          const DreamImage(
            fileName: 'removed_test.img',
            width: 120,
            height: 80,
          ),
        ],
        links: [sampleWeb],
      );
      await controller.selectDate(date);
      controller.contentChanged('');
      controller.removeImage(state().images.single);
      await controller.flushPendingSave();
      expect((await repo.getByDate(state().date))!.links, hasLength(1));
      controller.feedbackChanged(
        const DailyFeedback(sleepScore: 3, completed: true),
      );
      remove(state().links.single.id);
      await controller.flushPendingSave();
      expect((await repo.getByDate(state().date))!.feedback.sleepScore, 3);
      expect((await repo.getByDate(state().date))!.feedback.completed, isTrue);
    });

    test('打开失败显示资源错误但仍保留附件，多次打开只处理一次', () async {
      put();
      opener.gate = Completer<bool>();
      final opening = controller.openLink(
        date: state().date,
        loadRevision: controller.dateRevision,
        link: state().links.single,
      );
      await spin();
      expect(
        await controller.openLink(
          date: state().date,
          loadRevision: controller.dateRevision,
          link: state().links.single,
        ),
        isFalse,
      );
      expect(opener.opened, hasLength(1));
      opener.gate!.complete(false);
      expect(await opening, isFalse);
      expect(state().attachmentError, isNotNull);
      expect(state().links, hasLength(1));
    });
  });
}

class LinkTestOpener implements ILinkOpener {
  final List<DreamLink> opened = [];
  Completer<bool>? gate;
  @override
  Future<bool> open(DreamLink link) async {
    opened.add(link);
    return gate?.future ?? true;
  }
}
