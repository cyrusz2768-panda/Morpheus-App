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
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(Key('nav-$name')));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('dream-content-field')))
      .controller!
      .text;

  testWidgets('底栏先保存最新草稿；修改不增天数、清空删除更新统计', (tester) async {
    await show(tester);
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '人工测试梦境',
    );
    await tab(tester, 'statistics');
    expect(find.text('1 天'), findsOneWidget);
    expect((await repository.getByDate(DateTime.now()))!.content, '人工测试梦境');
    await tab(tester, 'record');
    expect(text(tester), '人工测试梦境');
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '修改后的人工测试梦境',
    );
    await tab(tester, 'statistics');
    expect(find.byKey(const Key('statistics-recorded-days')), findsOneWidget);
    expect(find.text('1 天'), findsOneWidget);
    await tab(tester, 'record');
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '\n\t　',
    );
    await tab(tester, 'statistics');
    expect(find.text('0 天'), findsOneWidget);
    expect(find.byKey(const Key('statistics-empty')), findsOneWidget);
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
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await tab(tester, 'statistics');
    expect(find.text('1 天'), findsOneWidget);
  });

  testWidgets('底栏日历选日回记录，补记归属旧月而非今天', (tester) async {
    final today = DateTime.now();
    final old = DateTime(today.year, today.month - 1, 1);
    await repository.save(date: old, content: '旧月测试梦境');
    await show(tester);
    await tab(tester, 'calendar');
    await tester.tap(find.byKey(const Key('calendar-previous-month')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('calendar-day-${DreamEntry.dateKey(old)}')),
    );
    await tester.pumpAndSettle();
    expect(text(tester), '旧月测试梦境');
    expect(container.read(dreamEditorControllerProvider).date, old);
    await tab(tester, 'statistics');
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(find.text('0 天'), findsOneWidget);
    await tester.tap(find.byKey(const Key('statistics-previous')));
    await tester.pumpAndSettle();
    expect(find.text('1 天'), findsOneWidget);
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
      await tab(tester, name);
      notifications.onTap!();
      await tester.pumpAndSettle();
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
    notifications.onTap!();
    await tester.pump();
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .onDestinationSelected,
      isNull,
    );
    repository.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(text(tester), '等待写入的测试梦境');
    expect(find.text('梦境统计'), findsNothing);
    expect(
      tester
          .widget<MainBottomNavigation>(find.byType(MainBottomNavigation))
          .selectedIndex,
      0,
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
  }) async {
    if (failSave) throw StateError('测试保存失败');
    await saveGate?.future;
    return super.save(date: date, content: content);
  }
}

/// 流的实时性由真实SQLite测试覆盖；导航测试用当前已提交快照验证实际路由接线。
class _Projection implements IStatisticsRepository, ICalendarRepository {
  _Projection(this.repository);
  final InMemoryDreamRepository repository;
  @override
  Stream<Set<String>> watchRecordedDates(StatisticsWindow window) async* {
    yield (await repository.getAll())
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
