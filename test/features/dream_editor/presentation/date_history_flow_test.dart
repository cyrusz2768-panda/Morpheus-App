import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_calendar/application/recorded_dream_dates_provider.dart';
import 'package:morpheus/features/dream_calendar/data/calendar_repository.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';

import '../../reminders/reminder_fakes.dart';

void main() {
  testWidgets('历史按梦境日期倒序，点击旧记录后可查看并回到今天', (tester) async {
    final repository = _HistoryRepository();
    final today = DreamEntry.dateOnly(DateTime.now());
    final yesterday = _daysBefore(today, 1);
    final earlier = _daysBefore(today, 2);

    // 故意打乱插入顺序，防止列表误用“写入顺序”作为梦境日期顺序。
    await repository.save(date: yesterday, content: '昨天梦见一片海');
    await repository.save(date: today, content: '今天梦见一座山');
    await repository.save(date: earlier, content: '前天梦见一座城');
    await _showApp(tester, repository);
    await _openHistory(tester);

    final todayRow = find.byKey(_historyKey(today));
    final yesterdayRow = find.byKey(_historyKey(yesterday));
    final earlierRow = find.byKey(_historyKey(earlier));
    expect(
      tester.getTopLeft(todayRow).dy,
      lessThan(tester.getTopLeft(yesterdayRow).dy),
    );
    expect(
      tester.getTopLeft(yesterdayRow).dy,
      lessThan(tester.getTopLeft(earlierRow).dy),
    );

    await tester.tap(yesterdayRow);
    await tester.pumpAndSettle();
    expect(find.text(_displayDate(yesterday)), findsOneWidget);
    expect(_editorText(tester), '昨天梦见一片海');

    await tester.tap(find.byKey(const Key('back-to-today-button')));
    await tester.pumpAndSettle();
    expect(find.text(_displayDate(today)), findsOneWidget);
    expect(_editorText(tester), '今天梦见一座山');
  });

  testWidgets('输入后立即打开历史，会在防抖计时结束前保存草稿', (tester) async {
    final repository = _HistoryRepository();
    final today = DreamEntry.dateOnly(DateTime.now());
    await _showApp(tester, repository);

    const draft = '还没有等到八百毫秒的新梦境';
    await tester.enterText(find.byKey(const Key('dream-content-field')), draft);
    await tester.pump();
    expect(await repository.getByDate(today), isNull);

    await tester.tap(find.byKey(const Key('open-history-button')));
    // pump() 不推进假时钟：此时能读到草稿，就能证明不是 800ms 定时器
    // 恰好帮我们存好了，而是导航入口确实先提交并等待了写入。
    await tester.pump();
    await tester.pump();
    expect((await repository.getByDate(today))?.content, draft);

    await tester.pumpAndSettle();
    expect(find.byKey(_historyKey(today)), findsOneWidget);
    expect(find.text(draft), findsOneWidget);
  });

  testWidgets('没有任何记录时显示历史空态', (tester) async {
    final repository = _HistoryRepository();
    await _showApp(tester, repository);
    await _openHistory(tester);

    expect(find.text('还没有梦境记录'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(await repository.getAll(), isEmpty);
  });

  testWidgets('打开历史等待期间到达的最后一段输入，也先保存再进入列表', (tester) async {
    final repository = _HistoryRepository();
    await _showApp(tester, repository);
    final field = tester.widget<TextField>(
      find.byKey(const Key('dream-content-field')),
    );
    final historyButton = tester.widget<IconButton>(
      find.byKey(const Key('open-history-button')),
    );

    // 精确复现同一次事件循环里的相邻回调：导航先认为没有待保存内容，
    // 输入法却在 await 续体之前交付最后一段文字。其它测试已经覆盖真实点击；
    // 此处直接调用公开回调，是为了稳定控制这个极小的异步窗口。
    historyButton.onPressed!();
    const lastInput = '输入法刚刚交付的最后一段梦境';
    field.onChanged!(lastInput);
    await tester.pumpAndSettle();

    expect((await repository.getByDate(DateTime.now()))?.content, lastInput);
    expect(find.text(lastInput), findsOneWidget);
    expect(find.byKey(_historyKey(DateTime.now())), findsOneWidget);
  });

  testWidgets('历史查询失败后点击重试，可以恢复记录列表', (tester) async {
    final repository = _HistoryRepository();
    final yesterday = _daysBefore(DreamEntry.dateOnly(DateTime.now()), 1);
    await repository.save(date: yesterday, content: '磁盘读取恢复后应出现的梦境');
    repository.historyFailures = 1;
    await _showApp(tester, repository);
    await _openHistory(tester);

    expect(find.text('读取历史梦境失败，请重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.byKey(_historyKey(yesterday)), findsOneWidget);
    expect(find.text('读取历史梦境失败，请重试。'), findsNothing);
    expect(repository.historyReads, greaterThanOrEqualTo(2));
  });

  testWidgets('清空旧日期的正文后重新打开历史，该记录不再出现', (tester) async {
    final repository = _HistoryRepository();
    final today = DreamEntry.dateOnly(DateTime.now());
    final yesterday = _daysBefore(today, 1);
    await repository.save(date: today, content: '今天的记录继续保留');
    await repository.save(date: yesterday, content: '待删除的旧日期记录');
    await _showApp(tester, repository);
    await _openHistory(tester);
    await tester.tap(find.byKey(_historyKey(yesterday)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('dream-content-field')), '');
    // 直接打开历史，既验证“离开编辑页前处理删除”，也验证列表会重新查询，
    // 而不是继续使用进入编辑器之前的过期缓存。
    await _openHistory(tester);

    expect(find.byKey(_historyKey(yesterday)), findsNothing);
    expect(find.byKey(_historyKey(today)), findsOneWidget);
    expect(await repository.getByDate(yesterday), isNull);
  });

  testWidgets('日期选择器取消后，日期和已有草稿保持不变', (tester) async {
    final repository = _HistoryRepository();
    final today = DreamEntry.dateOnly(DateTime.now());
    await _showApp(tester, repository);
    const draft = '打开日期对话框之前正在输入的草稿';
    await tester.enterText(find.byKey(const Key('dream-content-field')), draft);

    await tester.tap(find.byKey(const Key('select-date-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-jump-date-button')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    // 取消快速选择只关闭选择器，继续留在月历；返回后原日期和正文保持。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(_displayDate(today)), findsOneWidget);
    expect(_editorText(tester), draft);
  });

  testWidgets('在日期选择器确定昨天后，读取对应日期的梦境', (tester) async {
    final repository = _HistoryRepository();
    final today = DreamEntry.dateOnly(DateTime.now());
    final yesterday = _daysBefore(today, 1);
    await repository.save(date: today, content: '今天的内容');
    await repository.save(date: yesterday, content: '通过日历找到昨天的内容');
    await _showApp(tester, repository);

    await tester.tap(find.byKey(const Key('select-date-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-jump-date-button')));
    await tester.pumpAndSettle();
    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(calendar.lastDate.isAfter(today), isFalse);

    // 使用 Flutter 日历公开的选日回调，再点击真实确认按钮。这会经过
    // DatePickerDialog -> 页面 -> Controller 的完整流程，也能稳定覆盖
    // “昨天刚好位于上个月”的边界，避免依赖某个月份网格的坐标。
    calendar.onDateChanged(yesterday);
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text(_displayDate(yesterday)), findsOneWidget);
    expect(_editorText(tester), '通过日历找到昨天的内容');
  });

  testWidgets('草稿保存失败时阻止进入历史，保留输入供重试', (tester) async {
    final repository = _HistoryRepository();
    await _showApp(tester, repository);
    repository.saveFailures = 1;
    const draft = '存储失败时也不能丢失的草稿';
    await tester.enterText(find.byKey(const Key('dream-content-field')), draft);

    await tester.tap(find.byKey(const Key('open-history-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dream-content-field')), findsOneWidget);
    expect(_editorText(tester), draft);
    expect(repository.historyReads, 0);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsOneWidget);
    expect((await repository.getByDate(DateTime.now()))?.content, draft);
    await _openHistory(tester);
    expect(find.byKey(_historyKey(DateTime.now())), findsOneWidget);
  });
}

/// 使用真实应用入口和路由，只替换磁盘仓库。这样的测试能发现“单独页面能
/// 显示，但实际导航没有接起来”或历史 Provider 误用了默认数据库的问题。
Future<void> _showApp(
  WidgetTester tester,
  InMemoryDreamRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repository),
        calendarRepositoryProvider.overrideWithValue(
          _CalendarDatesRepository(repository),
        ),
        reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
        reminderNotificationsProvider.overrideWithValue(
          FakeReminderNotifications(),
        ),
      ],
      child: const MorpheusApp(),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    // 主动卸载 ProviderScope，让路由监听器和防抖 Timer 按应用生命周期释放。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _openHistory(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-history-button')));
  await tester.pumpAndSettle();
}

String _editorText(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(const Key('dream-content-field')))
      .controller!
      .text;
}

Key _historyKey(DateTime date) =>
    Key('history-entry-${DreamEntry.dateKey(date)}');

String _displayDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';

/// 用日历构造函数跨天，避免在夏令时切换时把“前一天”当成固定 24 小时。
DateTime _daysBefore(DateTime date, int days) {
  return DateTime(date.year, date.month, date.day - days);
}

/// 只给历史读取和保存加入可控故障；其它行为仍使用真实内存仓库实现。
/// 不用操作用户数据库，也不依靠断网或随机延迟来制造失败。
class _HistoryRepository extends InMemoryDreamRepository {
  int historyReads = 0;
  int historyFailures = 0;
  int saveFailures = 0;

  @override
  Future<List<DreamEntry>> getAll() async {
    historyReads += 1;
    if (historyFailures > 0) {
      historyFailures -= 1;
      throw StateError('测试用历史读取故障');
    }
    return super.getAll();
  }

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
  }) async {
    if (saveFailures > 0) {
      saveFailures -= 1;
      throw StateError('测试用保存故障');
    }
    return super.save(date: date, content: content);
  }
}

/// 日期回归测试共享同一个内存仓库，避免新月历误读开发者的真实数据库。
class _CalendarDatesRepository implements ICalendarRepository {
  _CalendarDatesRepository(this.repository);
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
