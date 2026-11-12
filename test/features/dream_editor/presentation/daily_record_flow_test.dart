import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import '../../reminders/reminder_fakes.dart';

void main() {
  late _Repository repo;
  late ProviderContainer container;
  setUp(() {
    repo = _Repository();
    container = ProviderContainer(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repo),
        reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
        reminderNotificationsProvider.overrideWithValue(
          FakeReminderNotifications(),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MorpheusApp(),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  DreamEditorController getController() =>
      container.read(dreamEditorControllerProvider.notifier);
  DreamEditorState getState() => container.read(dreamEditorControllerProvider);

  for (final mood in ['good', 'nightmare']) {
    testWidgets('$mood 进入正文，评分独立保存，多选因素完成显示正文与反馈', (tester) async {
      await show(tester);
      expect(find.text('你昨晚做了什么梦？'), findsOneWidget);
      await tap(tester, 'daily-mood-$mood');
      expect(getState().feedback.sleepScore, isNull);
      await tester.enterText(
        find.byKey(const Key('dream-content-field')),
        '人工测试：云上的图书馆',
      );
      await tap(tester, 'daily-content-next');
      await tap(tester, 'daily-score-2');
      await tap(tester, 'daily-factor-stress');
      await tap(tester, 'daily-factor-caffeine');
      await tap(tester, 'daily-factor-stress');
      await tap(tester, 'daily-finish');
      expect(getState().step, DailyRecordStep.summary);
      expect(find.textContaining('夜行世界的探险'), findsOneWidget);
      final saved = (await repo.getByDate(DateTime.now()))!;
      expect(saved.content, '人工测试：云上的图书馆');
      expect(saved.feedback.sleepScore, 2);
      expect(saved.feedback.factors, {SleepFactor.caffeine});
      expect(saved.feedback.completed, isTrue);
      await tester.drag(
        find.byKey(const Key('daily-summary-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 分'), findsOneWidget);
    });
  }

  for (final mood in ['forgotten', 'noDream']) {
    testWidgets('$mood 跳过正文，跳过评分保持 null，历史可找回反馈', (tester) async {
      await show(tester);
      await tap(tester, 'daily-mood-$mood');
      expect(find.byKey(const Key('dream-content-field')), findsNothing);
      expect(find.text('你可以给昨晚的睡眠打多少分？'), findsOneWidget);
      await tap(tester, 'daily-skip');
      expect(getState().step, DailyRecordStep.summary);
      final saved = (await repo.getAll()).single;
      expect(saved.feedback.sleepScore, isNull);
      expect(saved.content, isEmpty);
      await tap(tester, 'open-history-button');
      expect(find.textContaining('睡眠自评：未填写'), findsOneWidget);
      await tap(tester, 'history-entry-${DreamEntry.dateKey(DateTime.now())}');
      expect(getState().step, DailyRecordStep.summary);
    });
  }

  testWidgets('全部跳过且正文为空显示结束语，不制造空历史或 0 分', (tester) async {
    await show(tester);
    await tap(tester, 'daily-skip');
    expect(find.byKey(const Key('dream-content-field')), findsOneWidget);
    await tap(tester, 'daily-skip');
    await tap(tester, 'daily-skip');
    expect(find.textContaining('我们今晚再见。'), findsOneWidget);
    expect(getState().feedback.sleepScore, isNull);
    expect(await repo.getAll(), isEmpty);
    expect((await repo.getByDate(DateTime.now()))!.feedback.completed, isTrue);
    await getController().selectDate(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await getController().selectDate(DateTime.now());
    await tester.pumpAndSettle();
    expect(getState().step, DailyRecordStep.summary);
  });

  testWidgets('评分后跳过因素，保留评分并结束', (tester) async {
    await show(tester);
    await tap(tester, 'daily-mood-noDream');
    await tap(tester, 'daily-score-5');
    await tap(tester, 'daily-skip');
    final saved = (await repo.getAll()).single;
    expect(saved.feedback.sleepScore, 5);
    expect(saved.feedback.factors, isEmpty);
    expect(getState().step, DailyRecordStep.summary);
  });

  testWidgets('切换状态前保存正文，只收起不清空，切回继续编辑', (tester) async {
    await show(tester);
    await tap(tester, 'daily-mood-good');
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '尚未防抖的人工草稿',
    );
    await tap(tester, 'daily-change-mood');
    await tap(tester, 'daily-mood-noDream');
    expect(find.byKey(const Key('dream-content-field')), findsNothing);
    expect((await repo.getByDate(DateTime.now()))!.content, '尚未防抖的人工草稿');
    await tap(tester, 'daily-skip');
    expect(find.byKey(const Key('daily-hidden-content')), findsOneWidget);
    await tap(tester, 'daily-edit-mood');
    await tap(tester, 'daily-mood-nightmare');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('dream-content-field')))
          .controller!
          .text,
      '尚未防抖的人工草稿',
    );
  });

  testWidgets('反馈保存失败不推进，重试不重新读取覆盖草稿', (tester) async {
    await show(tester);
    repo.fail = true;
    await tap(tester, 'daily-mood-nightmare');
    expect(getState().step, DailyRecordStep.mood);
    expect(find.text('重试'), findsOneWidget);
    expect(getState().feedback.mood, DreamMood.nightmare);
    repo.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await tap(tester, 'daily-mood-nightmare');
    expect(getState().step, DailyRecordStep.content);
  });

  testWidgets('写入期间新反馈与正文一起串行落盘，清空正文不删除反馈', (tester) async {
    await show(tester);
    final controller = getController();
    controller.contentChanged('旧人工正文');
    final gate = Completer<void>();
    repo.gate = gate;
    final saving = controller.saveNow();
    await tester.pump();
    controller.feedbackChanged(
      const DailyFeedback(sleepScore: 3, factors: {SleepFactor.travel}),
    );
    controller.contentChanged('最新人工正文');
    gate.complete();
    await saving;
    await tester.pumpAndSettle();
    expect((await repo.getAll()).single.feedback.sleepScore, 3);
    expect((await repo.getAll()).single.content, '最新人工正文');
    controller.contentChanged('');
    await controller.flushPendingSave();
    expect((await repo.getAll()).single.feedback.sleepScore, 3);
    controller.feedbackChanged(const DailyFeedback());
    await controller.flushPendingSave();
    expect(await repo.getAll(), isEmpty);
  });

  testWidgets('步骤写盘时禁用底栏，切日抢占后旧续体不推进新日期', (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await repo.save(date: yesterday, content: '人工历史正文');
    await show(tester);
    final controller = getController();
    await controller.selectDate(yesterday);
    await controller.moveTo(DailyRecordStep.mood);
    final gate = Completer<void>();
    repo.gate = gate;
    final advancing = controller.chooseMood(DreamMood.noDream);
    await tester.pump();
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .onDestinationSelected,
      isNull,
    );
    // 通知同样经 selectDate 切日；它允许抢占交互，旧步骤必须核对加载编号。
    final selecting = controller.selectDate(DateTime.now());
    gate.complete();
    await advancing;
    await selecting;
    await tester.pumpAndSettle();
    expect(getState().date, DreamEntry.dateOnly(DateTime.now()));
    expect(getState().step, DailyRecordStep.mood);
    expect(getState().isAdvancing, isFalse);
    expect((await repo.getByDate(yesterday))!.content, '人工历史正文');
    expect((await repo.getByDate(yesterday))!.feedback.mood, DreamMood.noDream);
  });

  testWidgets('窄屏大字号的多选和完成按钮可滚动操作', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester);
    await tap(tester, 'daily-mood-forgotten');
    await tap(tester, 'daily-score-4');
    await tap(tester, 'daily-factor-unsure');
    await tap(tester, 'daily-finish');
    expect(getState().feedback.factors, {SleepFactor.unsure});
    expect(tester.takeException(), isNull);
  });
}

class _Repository extends InMemoryDreamRepository {
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
    DailyFeedback? feedback,
  }) async {
    final pending = gate;
    gate = null;
    if (pending != null) await pending.future;
    if (fail) throw StateError('人工测试写入失败');
    return super.save(date: date, content: content, feedback: feedback);
  }
}
