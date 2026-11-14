import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_export/data/dream_export_output.dart';
import 'package:morpheus/features/dream_export/data/dream_export_renderer.dart';
import 'package:morpheus/features/dream_export/domain/dream_export_data.dart';
import 'package:morpheus/features/dream_export/presentation/dream_export_page.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/l10n/app_text.dart';
import '../dream_editor/image_attachment_test.dart' show ImageTestRepository;
import '../reminders/reminder_fakes.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
);

class _Renderer implements IDreamExportRenderer {
  final List<DreamExportData> rendered = [];
  bool fail = false;
  @override
  Future<DreamExportImage> render(
    DreamExportData data, {
    bool Function()? isCancelled,
  }) async {
    rendered.add(data);
    if (fail) throw DreamExportTooLarge();
    return DreamExportImage(_png, 1, 1);
  }
}

class _Output implements IDreamExportOutput {
  int saves = 0;
  int shares = 0;
  bool denied = false;
  Completer<void>? gate;
  final List<Uint8List> bytes = [];
  @override
  Future<void> save(DreamExportImage image, DateTime date) async {
    saves++;
    bytes.add(image.bytes);
    await gate?.future;
    if (denied) throw PlatformException(code: 'permissionDenied');
  }

  @override
  Future<void> share(DreamExportImage image, DateTime date, Rect origin) async {
    shares++;
    bytes.add(image.bytes);
    expect(origin.width, greaterThan(0));
    await gate?.future;
  }
}

void main() {
  late ImageTestRepository repository;
  late _Renderer renderer;
  late _Output output;
  late ProviderContainer container;
  DreamEditorController controller() =>
      container.read(dreamEditorControllerProvider.notifier);
  setUp(() {
    repository = ImageTestRepository();
    renderer = _Renderer();
    output = _Output();
    container = ProviderContainer(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repository),
        dreamExportRendererProvider.overrideWithValue(renderer),
        dreamExportOutputProvider.overrideWithValue(output),
        reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
        reminderNotificationsProvider.overrideWithValue(
          FakeReminderNotifications(),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MorpheusApp(),
      ),
    );
    await tester.pumpAndSettle();
    await controller().moveTo(DailyRecordStep.content);
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    await tester.tap(find.byKey(const Key('record-more-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享完整记录'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('防抖前分享等待最新草稿，并保持预览与保存分享同版', (tester) async {
    await show(tester);
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '人工最新正文🌙\n结尾',
    );
    await open(tester);
    expect(renderer.rendered.single.content, '人工最新正文🌙\n结尾');
    expect(
      (await repository.getByDate(renderer.rendered.single.date))!.content,
      renderer.rendered.single.content,
    );
    expect(find.byType(DreamExportPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('export-save')));
    await tester.pumpAndSettle();
    expect(find.text('已保存到相册'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(DreamExportPage)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-share')));
    await tester.pumpAndSettle();
    expect(output.saves, 1);
    expect(output.shares, 1);
    expect(output.bytes.every((b) => identical(b, _png)), isTrue);
  });

  testWidgets('保存正在写旧版本时继续输入，分享等待末版；保存失败不打开预览', (tester) async {
    await show(tester);
    repository.gate = Completer<void>();
    controller().contentChanged('人工旧版');
    final pending = controller().flushPendingSave();
    await tester.pump();
    controller().contentChanged('人工最后一版');
    await open(tester, settle: false);
    expect(renderer.rendered, isEmpty);
    repository.gate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(renderer.rendered.single.content, '人工最后一版');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    repository.fail = true;
    controller().contentChanged('失败仍保留的草稿');
    await open(tester);
    expect(renderer.rendered.length, 1);
    expect(container.read(dreamEditorControllerProvider).content, '失败仍保留的草稿');
    expect(find.byType(DreamExportPage), findsNothing);
  });

  testWidgets('空记录提示，读取失败禁用入口', (tester) async {
    await show(tester);
    await open(tester);
    expect(find.text('这一天还没有可分享的文字、图片或链接。'), findsOneWidget);
    expect(renderer.rendered, isEmpty);
    repository.readFails = true;
    await controller().selectDate(DateTime(2026, 1, 1));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const Key('record-more-actions')),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('生成失败可重试，相册拒绝后仍可分享；输出中禁止重复点击', (tester) async {
    await repository.save(date: DateTime.now(), content: '人工测试');
    renderer.fail = true;
    await show(tester);
    await open(tester);
    expect(find.text('记录过长，暂时无法生成单张长图。请减少本次内容后重试。'), findsOneWidget);
    renderer.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    output.denied = true;
    await tester.tap(find.byKey(const Key('export-save')));
    await tester.pumpAndSettle();
    expect(find.text('未获得添加照片权限，请在系统设置中允许后重试。仍可使用系统分享。'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(DreamExportPage)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    output.gate = Completer<void>();
    await tester.tap(find.byKey(const Key('export-share')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('export-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('export-share')))
          .onPressed,
      isNull,
    );
    output.gate!.complete();
    await tester.pumpAndSettle();
    expect(output.shares, 1);
  });

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets('预览窄屏横屏三倍字号仍可滚动访问操作 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: morpheusLocale,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3)),
              child: child!,
            ),
            home: DreamExportPage(
              data: DreamExportData(
                date: DateTime(2026, 11, 14),
                content: '人工测试',
                images: [],
                links: [],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final button = find.byKey(const Key('export-share'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(output.shares, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
