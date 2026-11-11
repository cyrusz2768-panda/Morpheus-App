import 'package:morpheus/features/reminders/data/reminder_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_calendar/application/recorded_dream_dates_provider.dart';
import 'package:morpheus/features/dream_calendar/data/calendar_repository.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';

import '../reminders/reminder_fakes.dart';

void main() {
  late _CalendarDreamRepository repository;
  late FakeReminderNotifications notifications;
  late ProviderContainer container;

  setUp(() {
    repository = _CalendarDreamRepository();
    notifications = FakeReminderNotifications();
    container = ProviderContainer(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repository),
        calendarRepositoryProvider.overrideWithValue(
          _CalendarProjection(repository),
        ),
        reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
        reminderNotificationsProvider.overrideWithValue(notifications),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> showApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MorpheusApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCalendar(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('select-date-button')));
    await tester.pumpAndSettle();
  }

  Future<void> selectDay(WidgetTester tester, DateTime date) async {
    final day = find.byKey(Key('calendar-day-${DreamEntry.dateKey(date)}'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
  }

  String content(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('dream-content-field')))
      .controller!
      .text;

  Finder marker(DateTime date) =>
      find.byKey(Key('calendar-marker-${DreamEntry.dateKey(date)}'));

  testWidgets('补记旧日期立即进入月历有标记，清空后标记消失，今天的记录保留', (tester) async {
    final today = DreamEntry.dateOnly(DateTime.now());
    // 取本月较早的一天，月初当天则先以今天完成新增/清空联动。
    final earlier = DateTime(
      today.year,
      today.month,
      today.day > 1 ? today.day - 1 : today.day,
    );
    if (earlier != today) {
      await repository.save(date: today, content: '今天已有的测试梦境');
    }
    await showApp(tester);
    await openCalendar(tester);
    expect(marker(earlier), findsNothing);
    await selectDay(tester, earlier);
    expect(content(tester), isEmpty);

    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '月历补记的测试内容',
    );
    // 不等待 800ms，直接进入月历：标记必须来自导航前提交成功的记录。
    await openCalendar(tester);
    expect(marker(earlier), findsOneWidget);
    await selectDay(tester, earlier);
    expect(content(tester), '月历补记的测试内容');

    await tester.enterText(find.byKey(const Key('dream-content-field')), '');
    await openCalendar(tester);
    expect(marker(earlier), findsNothing);
    expect(await repository.getByDate(earlier), isNull);
    if (earlier != today) {
      expect(marker(today), findsOneWidget);
      await selectDay(tester, today);
      expect(content(tester), '今天已有的测试梦境');
    }
  });

  testWidgets('有记录日期点击后读取正文，返回月历时仍显示原记录标记', (tester) async {
    final today = DreamEntry.dateOnly(DateTime.now());
    final first = DateTime(today.year, today.month, 1);
    await repository.save(date: first, content: '月初已有的测试记录');
    await showApp(tester);
    await openCalendar(tester);
    expect(marker(first), findsOneWidget);
    await selectDay(tester, first);
    expect(container.read(dreamEditorControllerProvider).date, first);
    expect(content(tester), '月初已有的测试记录');
    await openCalendar(tester);
    expect(marker(first), findsOneWidget);
  });

  testWidgets('跨年月份切换显示正确标记，回到今天切回本月', (tester) async {
    final december = DateTime(2025, 12, 31);
    final january = DateTime(2026, 1, 1);
    await repository.save(date: december, content: '跨年前的测试内容');
    await repository.save(date: january, content: '跨年后的测试内容');
    await showApp(tester);
    await container
        .read(dreamEditorControllerProvider.notifier)
        .selectDate(january);
    await tester.pumpAndSettle();
    await openCalendar(tester);
    expect(marker(january), findsOneWidget);
    expect(marker(december), findsNothing);
    await tester.tap(find.byKey(const Key('calendar-previous-month')));
    await tester.pumpAndSettle();
    expect(marker(december), findsOneWidget);
    expect(marker(january), findsNothing);
    await tester.tap(find.byKey(const Key('calendar-today-button')));
    await tester.pumpAndSettle();
    final today = DateTime.now();
    expect(
      find.byKey(Key('calendar-day-${DreamEntry.dateKey(today)}')),
      findsOneWidget,
    );
  });

  testWidgets('打开月历的 await 间隙收到末尾输入时，也先保存再显示标记', (tester) async {
    await showApp(tester);
    final field = tester.widget<TextField>(
      find.byKey(const Key('dream-content-field')),
    );
    final calendarButton = tester.widget<IconButton>(
      find.byKey(const Key('select-date-button')),
    );
    calendarButton.onPressed!();
    field.onChanged!('输入法刚交付的测试草稿');
    await tester.pumpAndSettle();
    expect(
      (await repository.getByDate(DateTime.now()))!.content,
      '输入法刚交付的测试草稿',
    );
    expect(marker(DateTime.now()), findsOneWidget);
  });

  testWidgets('保存失败时阻止进入月历，保留草稿并可重试', (tester) async {
    await showApp(tester);
    repository.saveFailures = 1;
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '保存失败时保留的测试草稿',
    );
    await openCalendar(tester);
    expect(find.text('梦境月历'), findsNothing);
    expect(content(tester), '保存失败时保留的测试草稿');
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await openCalendar(tester);
    expect(marker(DateTime.now()), findsOneWidget);
  });

  testWidgets('月历打开期间点击提醒通知，关闭月历并读取当天记录', (tester) async {
    final today = DreamEntry.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    await repository.save(date: today, content: '通知返回的当天测试内容');
    await repository.save(date: yesterday, content: '原日期的测试内容');
    await showApp(tester);
    await container
        .read(dreamEditorControllerProvider.notifier)
        .selectDate(yesterday);
    await tester.pumpAndSettle();
    await openCalendar(tester);
    notifications.onTap!(ReminderDestination.today);
    await tester.pumpAndSettle();
    expect(find.text('梦境月历'), findsNothing);
    expect(container.read(dreamEditorControllerProvider).date, today);
    expect(content(tester), '通知返回的当天测试内容');
    expect((await repository.getByDate(yesterday))!.content, '原日期的测试内容');
  });
}

class _CalendarDreamRepository extends InMemoryDreamRepository {
  int saveFailures = 0;

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
  }) async {
    if (saveFailures > 0) {
      saveFailures--;
      throw StateError('Scripted calendar navigation save failure');
    }
    return super.save(date: date, content: content);
  }
}

/// 路由测试只验证每次打开月历时的快照；实时订阅由页面和真实 Drift 测试覆盖。
class _CalendarProjection implements ICalendarRepository {
  _CalendarProjection(this.repository);
  final InMemoryDreamRepository repository;

  @override
  Stream<Set<String>> watchRecordedDatesInMonth(DateTime month) async* {
    final entries = await repository.getAll();
    yield entries
        .where(
          (entry) =>
              entry.dreamDate.year == month.year &&
              entry.dreamDate.month == month.month,
        )
        .map((entry) => DreamEntry.dateKey(entry.dreamDate))
        .toSet();
  }
}
