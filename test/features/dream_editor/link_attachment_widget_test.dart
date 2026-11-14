import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/link_opener.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import '../reminders/reminder_fakes.dart';
import 'image_attachment_test.dart' show ImageTestRepository;
import 'link_attachment_test.dart' show LinkTestOpener, sampleWeb;

void main() {
  late ImageTestRepository repo;
  late LinkTestOpener opener;
  late ProviderContainer container;
  late DreamEditorController controller;
  DreamEditorState state() => container.read(dreamEditorControllerProvider);
  setUp(() {
    repo = ImageTestRepository();
    opener = LinkTestOpener();
    container = ProviderContainer(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repo),
        linkOpenerProvider.overrideWithValue(opener),
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
    controller = container.read(dreamEditorControllerProvider.notifier);
    await controller.moveTo(DailyRecordStep.content);
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String kind) async {
    await tapKey(tester, 'add-attachment-button');
    await tapKey(tester, 'add-$kind-link-menu-item');
  }

  testWidgets('完整记录页正文网址高亮并可点开，保存仍为原文，无效网址静默', (tester) async {
    await show(tester);
    const content = '人工 example.com，example..com';
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      content,
    );
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final text = editable.renderEditable.text! as TextSpan;
    final highlighted = text.children!.whereType<TextSpan>().where(
      (s) => s.style?.color != null,
    );
    expect(highlighted.single.text, 'example.com');
    final linkBox = editable.renderEditable
        .getBoxesForSelection(
          const TextSelection(baseOffset: 3, extentOffset: 14),
        )
        .last
        .toRect();
    // 覆盖末字右半边，不能只按最近插入点的排他end判断。
    await tester.tapAt(
      editable.renderEditable.localToGlobal(
        Offset(linkBox.right - 1, linkBox.center.dy),
      ),
    );
    await tester.pumpAndSettle();
    expect(opener.opened.single.url, 'https://example.com');
    expect((await repo.getByDate(state().date))!.content, content);
    expect(state().links, isEmpty);
    expect(state().attachmentError, isNull);
    final invalidBox = editable.renderEditable
        .getBoxesForSelection(
          const TextSelection(baseOffset: 15, extentOffset: 27),
        )
        .first
        .toRect();
    await tester.tapAt(
      editable.renderEditable.localToGlobal(invalidBox.center),
    );
    await tester.pumpAndSettle();
    expect(opener.opened, hasLength(1));
    expect(state().attachmentError, isNull);
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('加号上方菜单图片网页音乐从上到下排列且表单可操作，字号$scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(tester);
      await tapKey(tester, 'add-attachment-button');
      final image = find.byKey(const Key('add-image-menu-item'));
      final web = find.byKey(const Key('add-web-link-menu-item'));
      final music = find.byKey(const Key('add-music-link-menu-item'));
      expect(tester.getTopLeft(image).dy, lessThan(tester.getTopLeft(web).dy));
      expect(tester.getTopLeft(web).dy, lessThan(tester.getTopLeft(music).dy));
      expect(
        tester.getBottomLeft(music).dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('add-attachment-button'))).dy,
        ),
      );
      await tester.tap(music);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('link-url-field')),
        'https://open.spotify.com/track/artificial',
      );
      await tester.enterText(find.byKey(const Key('link-title-field')), '人工音乐');
      await tapKey(tester, 'save-link-button');
      await controller.flushPendingSave();
      expect(state().links.single.kind, DreamLinkKind.music);
      expect((await repo.getByDate(state().date))!.links.single.title, '人工音乐');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('链接必填标题可选，无效输入或取消不增加记录，留空标题显示原URL', (tester) async {
    await show(tester);
    await menu(tester, 'web');
    await tester.enterText(
      find.byKey(const Key('link-url-field')),
      'javascript:alert(1)',
    );
    await tapKey(tester, 'save-link-button');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(state().links, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(state().links, isEmpty);
    await menu(tester, 'web');
    await tester.enterText(
      find.byKey(const Key('link-url-field')),
      'example.com/no-title',
    );
    await tapKey(tester, 'save-link-button');
    expect(state().links.single.title, isNull);
    expect(find.text('https://example.com/no-title'), findsOneWidget);
    await controller.flushPendingSave();
  });

  testWidgets('修改链接/清除标题/删除均保存同一日期，打开先保存最新草稿', (tester) async {
    await repo.save(date: DateTime.now(), content: '', links: [sampleWeb]);
    await show(tester);
    await tapKey(tester, 'link-options-${sampleWeb.id}');
    await tester.tap(find.text('修改链接'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('link-url-field')),
      'https://example.com/edited',
    );
    await tester.enterText(find.byKey(const Key('link-title-field')), '');
    await tapKey(tester, 'save-link-button');
    expect(state().links.single.id, sampleWeb.id);
    expect(state().links.single.title, isNull);
    await tapKey(tester, 'dream-link-${sampleWeb.id}');
    expect(opener.opened.single.url, 'https://example.com/edited');
    expect(
      (await repo.getByDate(state().date))!.links.single.url,
      'https://example.com/edited',
    );
    await tapKey(tester, 'link-options-${sampleWeb.id}');
    await tester.tap(find.text('删除链接'));
    await tester.pumpAndSettle();
    await controller.flushPendingSave();
    expect(state().links, isEmpty);
    expect(await repo.getByDate(state().date), isNull);
  });

  testWidgets('表单期间切日后提交不会写入新日期，分类收起正文时仍可查看已有链接', (tester) async {
    await repo.save(
      date: DateTime.now(),
      content: '',
      links: [sampleWeb],
      feedback: const DailyFeedback(mood: DreamMood.forgotten, completed: true),
    );
    await show(tester);
    await controller.moveTo(DailyRecordStep.summary);
    await tester.pumpAndSettle();
    await tapKey(tester, 'daily-hidden-content');
    expect(find.byKey(ValueKey('dream-link-${sampleWeb.id}')), findsOneWidget);
    await controller.moveTo(DailyRecordStep.content);
    await tester.pumpAndSettle();
    await menu(tester, 'music');
    final previousDate = state().date;
    await controller.selectDate(previousDate.subtract(const Duration(days: 1)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('link-url-field')),
      'https://music.apple.com/cn/album/artificial/123',
    );
    await tapKey(tester, 'save-link-button');
    expect(state().links, isEmpty);
    expect(await repo.getByDate(state().date), isNull);
    expect((await repo.getByDate(previousDate))!.links.single.id, sampleWeb.id);
  });
}
