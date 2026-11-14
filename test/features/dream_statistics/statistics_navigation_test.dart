import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';
import '../../helpers/daily_record_test_helper.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/reminders/data/reminder_notifications.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/app/main_bottom_navigation.dart';
import 'package:morpheus/features/dream_calendar/application/recorded_dream_dates_provider.dart';
import 'package:morpheus/features/dream_calendar/data/calendar_repository.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_statistics/application/statistics_provider.dart';
import 'package:morpheus/features/dream_statistics/data/statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import '../reminders/reminder_fakes.dart';

void main() {
  late _Repository repository;
  late FakeReminderNotifications notifications;
  late ProviderContainer container;
  setUp(() {
    repository = _Repository();
    notifications = FakeReminderNotifications();
    container = ProviderContainer(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repository),
        statisticsRepositoryProvider.overrideWithValue(_Projection(repository)),
        calendarRepositoryProvider.overrideWithValue(_Projection(repository)),
        reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
        reminderNotificationsProvider.overrideWithValue(notifications),
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
    await openDreamTextIfPrompted(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(Key('nav-$name')));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
  }

  String text(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('dream-content-field')))
      .controller!
      .text;

  testWidgets('底栏先保存最新草稿；修改和清空后仍可查看反馈统计', (tester) async {
    await show(tester);
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '人工测试梦境',
    );
    await tab(tester, 'statistics');
    expect(find.byKey(const Key('statistics-mood-insight')), findsOneWidget);
    expect((await repository.getByDate(DateTime.now()))!.content, '人工测试梦境');
    await tab(tester, 'record');
    expect(text(tester), '人工测试梦境');
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '修改后的人工测试梦境',
    );
    await tab(tester, 'statistics');
    expect(find.byKey(const Key('statistics-status-chart')), findsOneWidget);
    expect(find.byKey(const Key('statistics-mood-insight')), findsOneWidget);
    await tab(tester, 'record');
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '\n\t　',
    );
    await tab(tester, 'statistics');
    expect(find.byKey(const Key('statistics-mood-insight')), findsOneWidget);
    expect(find.byKey(const Key('statistics-mood-insight')), findsOneWidget);
    expect(await repository.getByDate(DateTime.now()), isNull);
  });

  testWidgets('底栏 await 间隙收到末尾文字仍完整保存，顶栏不并发导航', (tester) async {
    await show(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    bar.onDestinationSelected!(1);
    final search = tester.widget<IconButton>(
      find.byKey(const Key('open-search-button')),
    );
    search.onPressed!();
    container
        .read(dreamEditorControllerProvider.notifier)
        .contentChanged('输入法最后交付');
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(find.text('梦境统计'), findsOneWidget);
    expect(find.byKey(const Key('dream-search-field')), findsNothing);
    expect((await repository.getByDate(DateTime.now()))!.content, '输入法最后交付');
  });

  testWidgets('保存失败阻止切换、保留草稿，重试后可进入统计', (tester) async {
    await show(tester);
    repository.failSave = true;
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '失败保留草稿',
    );
    await tab(tester, 'statistics');
    expect(text(tester), '失败保留草稿');
    expect(find.text('梦境统计'), findsNothing);
    repository.failSave = false;
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    await tab(tester, 'statistics');
    expect(find.byKey(const Key('statistics-mood-insight')), findsOneWidget);
  });

  testWidgets('底栏日历选日回记录，补记归属旧月而非今天', (tester) async {
    final today = DateTime.now();
    final old = DateTime(today.year, today.month - 1, 1);
    await repository.save(date: old, content: '旧月测试梦境');
    await show(tester);
    await tab(tester, 'calendar');
    await tester.tap(find.byKey(const Key('calendar-previous-month')));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    await tester.tap(
      find.byKey(Key('calendar-day-${DreamEntry.dateKey(old)}')),
    );
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(text(tester), '旧月测试梦境');
    expect(container.read(dreamEditorControllerProvider).date, old);
    await tab(tester, 'statistics');
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(find.byKey(const Key('statistics-mood-insight')), findsOneWidget);
    await tester.tap(find.byKey(const Key('statistics-previous')));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(find.byKey(const Key('statistics-mood-insight')), findsOneWidget);
  });

  for (final name in ['statistics', 'calendar']) {
    testWidgets('$name页点击提醒通知回当天，底栏恢复记录选中', (tester) async {
      final today = DreamEntry.dateOnly(DateTime.now());
      final old = DateTime(today.year, today.month, today.day - 1);
      await repository.save(date: today, content: '当天测试梦境');
      await show(tester);
      await container
          .read(dreamEditorControllerProvider.notifier)
          .selectDate(old);
      await tester.pumpAndSettle();
      await openDreamTextIfPrompted(tester);
      await tab(tester, name);
      notifications.onTap!(ReminderDestination.today);
      await tester.pumpAndSettle();
      await openDreamTextIfPrompted(tester);
      expect(text(tester), '当天测试梦境');
      expect(
        tester
            .widget<MainBottomNavigation>(find.byType(MainBottomNavigation))
            .selectedIndex,
        0,
      );
    });
  }

  testWidgets('通知撤销保存等待中的旧tab意图，并在等待期间阻止新导航', (tester) async {
    await show(tester);
    repository.saveGate = Completer<void>();
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '等待写入的测试梦境',
    );
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(1);
    await tester.pump();
    notifications.onTap!(ReminderDestination.today);
    await tester.pump();
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .onDestinationSelected,
      isNull,
    );
    repository.saveGate!.complete();
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(text(tester), '等待写入的测试梦境');
    expect(find.text('梦境统计'), findsNothing);
    expect(
      tester
          .widget<MainBottomNavigation>(find.byType(MainBottomNavigation))
          .selectedIndex,
      0,
    );
  });

  String currentWeekRange() {
    final window = StatisticsWindow(StatisticsPeriod.week, DateTime.now());
    final end = DateTime(window.end.year, window.end.month, window.end.day - 1);
    String date(DateTime d) => '${d.year}.${d.month}.${d.day}';
    return '${date(window.start)} — ${date(end)}';
  }

  testWidgets('编辑中回顾通知保存完整草稿，显示点击时自然周起止日期', (tester) async {
    await show(tester);
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '回顾通知前的测试草稿',
    );
    notifications.onTap!(ReminderDestination.weeklyStatistics);
    container
        .read(dreamEditorControllerProvider.notifier)
        .contentChanged('回顾通知前的测试草稿及末尾');
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(find.text('梦境统计'), findsOneWidget);
    expect(
      (await repository.getByDate(DateTime.now()))!.content,
      '回顾通知前的测试草稿及末尾',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('statistics-range'))).data,
      currentWeekRange(),
    );
    expect(find.byKey(const Key('statistics-mood-insight')), findsOneWidget);
  });

  testWidgets('统计页月历史浏览收到回顾通知强制刷新最新周，重复点击也有效', (tester) async {
    await show(tester);
    await tab(tester, 'statistics');
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    await tester.tap(find.byKey(const Key('statistics-previous')));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    notifications.onTap!(ReminderDestination.weeklyStatistics);
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('statistics-range'))).data,
      currentWeekRange(),
    );
    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    notifications.onTap!(ReminderDestination.weeklyStatistics);
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('statistics-range'))).data,
      currentWeekRange(),
    );
  });

  testWidgets('回顾保存失败保留草稿和日期，重试后再次点击可跳转', (tester) async {
    await show(tester);
    final old = DateTime(2026, 1, 2);
    await container
        .read(dreamEditorControllerProvider.notifier)
        .selectDate(old);
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    repository.failSave = true;
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '回顾失败保留草稿',
    );
    notifications.onTap!(ReminderDestination.weeklyStatistics);
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(text(tester), '回顾失败保留草稿');
    expect(container.read(dreamEditorControllerProvider).date, old);
    repository.failSave = false;
    notifications.onTap!(ReminderDestination.weeklyStatistics);
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(find.text('梦境统计'), findsOneWidget);
    expect((await repository.getByDate(old))!.content, '回顾失败保留草稿');
  });

  for (final latest in [
    ReminderDestination.weeklyStatistics,
    ReminderDestination.today,
  ]) {
    testWidgets('保存等待中通知交替以最后$latest为准', (tester) async {
      await show(tester);
      repository.saveGate = Completer<void>();
      await tester.enterText(
        find.byKey(const Key('dream-content-field')),
        '交替通知草稿',
      );
      notifications.onTap!(
        latest == ReminderDestination.today
            ? ReminderDestination.weeklyStatistics
            : ReminderDestination.today,
      );
      await tester.pump();
      notifications.onTap!(latest);
      repository.saveGate!.complete();
      await tester.pumpAndSettle();
      await openDreamTextIfPrompted(tester);
      if (latest == ReminderDestination.weeklyStatistics) {
        expect(find.text('梦境统计'), findsOneWidget);
      } else {
        expect(text(tester), '交替通知草稿');
      }
      expect((await repository.getByDate(DateTime.now()))!.content, '交替通知草稿');
    });
  }

  testWidgets('每周回顾复用状态比例、评分趋势和因素摘要，反馈无需正文', (tester) async {
    await repository.save(
      date: DateTime.now(),
      content: '',
      feedback: const DailyFeedback(
        mood: DreamMood.nightmare,
        sleepScore: 3,
        factors: {SleepFactor.screen, SleepFactor.stress},
      ),
    );
    await show(tester);
    notifications.onTap!(ReminderDestination.weeklyStatistics);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('statistics-status-chart')), findsOneWidget);
    expect(find.textContaining('都是噩梦。'), findsOneWidget);
    expect(find.text('好梦 0% · 噩梦 100%'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('statistics-score-average')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('statistics-score-average')))
          .data,
      '3.0 / 5 分',
    );
    expect(find.byKey(const Key('statistics-score-chart')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('statistics-factors-summary')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('本周你认为对睡眠影响较大的是压力和睡前屏幕。'), findsOneWidget);
    expect(find.text('记录天数'), findsNothing);
  });

  testWidgets('回顾冷启动在编辑器加载后打开最新周', (tester) async {
    notifications.launchedFromNotification = true;
    notifications.launchDestination = ReminderDestination.weeklyStatistics;
    await show(tester);
    expect(find.text('梦境统计'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('statistics-range'))).data,
      currentWeekRange(),
    );
  });
}

class _Repository extends InMemoryDreamRepository {
  bool failSave = false;
  Completer<void>? saveGate;
  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
    DailyFeedback? feedback,
    List<DreamImage>? images,
    List<DreamLink>? links,
  }) async {
    if (failSave) throw StateError('测试保存失败');
    await saveGate?.future;
    return super.save(date: date, content: content, feedback: feedback);
  }
}

/// 流的实时性由真实SQLite测试覆盖；导航测试用当前已提交快照验证实际路由接线。
class _Projection implements IStatisticsRepository, ICalendarRepository {
  _Projection(this.repository);
  final InMemoryDreamRepository repository;
  @override
  Stream<List<StatisticsRecord>> watchRecords(StatisticsWindow window) async* {
    yield (await repository.getAll())
        .map(
          (entry) => StatisticsRecord(
            date: entry.dreamDate,
            hasContent: entry.content.trim().isNotEmpty,
            feedback: entry.feedback,
          ),
        )
        .toList();
  }

  @override
  Stream<Set<String>> watchRecordedDates(StatisticsWindow window) async* {
    yield (await repository.getAll())
        .where((entry) => entry.content.trim().isNotEmpty)
        .map((entry) => DreamEntry.dateKey(entry.dreamDate))
        .toSet();
  }

  @override
  Stream<Set<String>> watchRecordedDatesInMonth(DateTime month) async* {
    yield (await repository.getAll())
        .where(
          (entry) =>
              entry.dreamDate.year == month.year &&
              entry.dreamDate.month == month.month,
        )
        .map((entry) => DreamEntry.dateKey(entry.dreamDate))
        .toSet();
  }
}
