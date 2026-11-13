import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/image_attachment_service.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import '../reminders/reminder_fakes.dart';
import 'image_attachment_test.dart'
    show ImageTestRepository, ImageTestService, image;

void main() {
  late ProviderContainer container;
  late ImageTestRepository repo;
  late ImageTestService service;
  setUp(() {
    repo = ImageTestRepository();
    service = ImageTestService();
    container = ProviderContainer(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repo),
        imageAttachmentServiceProvider.overrideWithValue(service),
        reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
        reminderNotificationsProvider.overrideWithValue(
          FakeReminderNotifications(),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<DreamEditorController> show(WidgetTester tester) async {
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
    final controller = container.read(dreamEditorControllerProvider.notifier);
    await controller.moveTo(DailyRecordStep.content);
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    return controller;
  }

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('加号上方显示单行菜单，点击后添加图片，大字号 $scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await show(tester);
      final plus = find.byKey(const Key('add-attachment-button'));
      await tester.ensureVisible(plus);
      await tester.tap(plus);
      await tester.pumpAndSettle();
      final item = find.byKey(const Key('add-image-menu-item'));
      expect(find.text('添加图片'), findsOneWidget);
      expect(
        tester.getRect(item).bottom,
        lessThanOrEqualTo(tester.getRect(plus).top),
      );
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(
        container.read(dreamEditorControllerProvider).images,
        hasLength(1),
      );
      expect((await repo.getByDate(DateTime.now()))!.images, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final attachment in [
    image,
    const DreamImage(fileName: 'tall-layout.img', width: 80, height: 120),
  ]) {
    testWidgets('无外框，图片完整展开并按自身高度推移加号及所有后续文字 ${attachment.fileName}', (
      tester,
    ) async {
      final controller = await show(tester);
      final field = find.byKey(const Key('dream-content-field'));
      expect(
        find.ancestor(
          of: field,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).border != null,
          ),
        ),
        findsNothing,
      );
      final following = [
        find.byKey(const Key('add-attachment-button')),
        find.byKey(const Key('daily-content-next')),
        find.byKey(const Key('daily-skip')),
        find.byKey(const Key('daily-change-mood')),
        find.byKey(const Key('save-status-label')),
      ];
      final oldTops = following
          .map((finder) => tester.getTopLeft(finder).dy)
          .toList();
      service.result = [attachment];
      await controller.addImage();
      await tester.pumpAndSettle();
      final thumbnail = find.byKey(
        ValueKey('dream-image-${attachment.fileName}'),
      );
      final rect = tester.getRect(thumbnail);
      expect(rect.width / rect.height, closeTo(attachment.aspectRatio, .01));
      for (var i = 0; i < following.length; i++) {
        // 图片上下各6px间距也属于它新增的文档高度。控件不再固定在旧视口里。
        expect(
          tester.getTopLeft(following[i]).dy - oldTops[i],
          closeTo(rect.height + 12, .01),
        );
      }
      expect(
        tester.getTopLeft(following.first).dy,
        greaterThanOrEqualTo(rect.bottom),
      );
      final imageScroll = find.ancestor(
        of: thumbnail,
        matching: find.byType(SingleChildScrollView),
      );
      final plusScroll = find.ancestor(
        of: following.first,
        matching: find.byType(SingleChildScrollView),
      );
      expect(imageScroll, findsOneWidget);
      expect(plusScroll, findsOneWidget);
      expect(tester.widget(imageScroll), same(tester.widget(plusScroll)));
      expect(
        tester.widget<SingleChildScrollView>(imageScroll).key,
        const Key('daily-content-scroll'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('缩略图等宽原比例、左右等空白；黑底大图右下角删除并保存', (tester) async {
    await repo.save(
      date: DateTime.now(),
      content: '人工图片测试',
      images: [
        image,
        const DreamImage(fileName: 'portrait.img', width: 80, height: 120),
      ],
    );
    final controller = await show(tester);
    final landscape = find.byKey(ValueKey('dream-image-${image.fileName}'));
    await tester.ensureVisible(landscape);
    await tester.pumpAndSettle();
    final rect = tester.getRect(landscape);
    final portrait = find.byKey(const ValueKey('dream-image-portrait.img'));
    expect(rect.width / rect.height, closeTo(1.5, .01));
    expect(tester.getSize(portrait).width, rect.width);
    final fieldRect = tester.getRect(
      find.byKey(const Key('dream-content-field')),
    );
    expect(
      rect.left - fieldRect.left,
      closeTo(fieldRect.right - rect.right, .01),
    );
    expect(rect.left - fieldRect.left, lessThanOrEqualTo(8));
    await tester.tap(landscape);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      Colors.black,
    );
    final trash = find.byKey(const Key('delete-full-image'));
    final screen = tester.getSize(find.byType(Dialog));
    expect(tester.getCenter(trash).dx, greaterThan(screen.width / 2));
    expect(tester.getCenter(trash).dy, greaterThan(screen.height / 2));
    await tester.tap(trash);
    await tester.pumpAndSettle();
    await controller.flushPendingSave();
    expect(
      (await repo.getByDate(DateTime.now()))!.images.single.fileName,
      'portrait.img',
    );
    expect((await repo.getByDate(DateTime.now()))!.content, '人工图片测试');
  });

  testWidgets('长按显示移除；忘记梦境的总结仍可展开图片', (tester) async {
    await repo.save(
      date: DateTime.now(),
      content: '',
      images: [image],
      feedback: const DailyFeedback(mood: DreamMood.forgotten, completed: true),
    );
    final controller = await show(tester);
    await controller.moveTo(DailyRecordStep.summary);
    await tester.pumpAndSettle();
    final hidden = find.byKey(const Key('daily-hidden-content'));
    await tester.ensureVisible(hidden);
    await tester.tap(hidden);
    await tester.pumpAndSettle();
    final thumbnail = find.byKey(ValueKey('dream-image-${image.fileName}'));
    await tester.ensureVisible(thumbnail);
    await tester.longPress(thumbnail);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除图片'));
    await tester.pumpAndSettle();
    await controller.flushPendingSave();
    final record = (await repo.getByDate(DateTime.now()))!;
    expect(record.images, isEmpty);
    expect(record.feedback.mood, DreamMood.forgotten);
  });
}
