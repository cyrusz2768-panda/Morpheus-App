import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/theme.dart';
import 'package:morpheus/features/dream_calendar/application/recorded_dream_dates_provider.dart';
import 'package:morpheus/features/dream_calendar/data/calendar_repository.dart';
import 'package:morpheus/features/dream_calendar/presentation/dream_calendar_page.dart';
import 'package:morpheus/l10n/app_text.dart';

void main() {
  late _CalendarRepository repository;
  final today = DateTime(2024, 3, 15);

  setUp(() => repository = _CalendarRepository());
  tearDown(() => repository.dispose());

  testWidgets('只在有记录的日期下方显示圆点，并提供日期和记录状态语义', (tester) async {
    repository.setDates(DateTime(2024, 3), {'2024-03-05', '2024-03-15'});
    await _showCalendar(tester, repository, today: today);

    expect(find.byKey(const Key('calendar-marker-2024-03-05')), findsOneWidget);
    expect(find.byKey(const Key('calendar-marker-2024-03-15')), findsOneWidget);
    expect(find.byKey(const Key('calendar-marker-2024-03-06')), findsNothing);
    expect(find.text('有梦境记录'), findsOneWidget);
    final todayCell = tester.widget<Semantics>(_day('2024-03-15'));
    expect(todayCell.properties.label, '2024年3月15日，今天，有梦境记录');
    expect(todayCell.properties.selected, isTrue);
    expect(todayCell.properties.onTap, isNotNull);
    expect(
      tester.widget<Semantics>(_day('2024-03-06')).properties.label,
      '2024年3月6日，无梦境记录',
    );
  });

  for (final recorded in [true, false]) {
    testWidgets('${recorded ? '有' : '无'}记录日期点击后把日期返回编辑器', (tester) async {
      if (recorded) {
        repository.setDates(DateTime(2024, 3), {'2024-03-05'});
      }
      final result = await _showCalendar(tester, repository, today: today);

      await tester.tap(_day('2024-03-05'));
      await tester.pumpAndSettle();

      expect(result.date, DateTime(2024, 3, 5));
      expect(find.byType(DreamCalendarPage), findsNothing);
    });
  }

  testWidgets('本月未来日期和向未来翻月均禁用', (tester) async {
    final result = await _showCalendar(tester, repository, today: today);
    final future = tester.widget<Semantics>(_day('2024-03-16'));
    expect(future.properties.enabled, isFalse);
    expect(future.properties.onTap, isNull);
    expect(future.properties.label, contains('未来日期不可选择'));
    expect(tester.widget<IconButton>(_nextMonth).onPressed, isNull);

    await tester.tap(_day('2024-03-16'));
    await tester.pumpAndSettle();
    expect(result.date, isNull);
    expect(find.byType(DreamCalendarPage), findsOneWidget);
  });

  testWidgets('跨年翻月正确，闰年二月有29日而普通二月只有28日', (tester) async {
    await _showCalendar(
      tester,
      repository,
      today: today,
      initialDate: DateTime(2024, 1, 31),
    );
    await tester.tap(_previousMonth);
    await tester.pumpAndSettle();
    expect(find.text('2023年12月'), findsOneWidget);
    expect(_day('2023-12-31'), findsOneWidget);

    await tester.tap(_nextMonth);
    await tester.pumpAndSettle();
    await tester.tap(_nextMonth);
    await tester.pumpAndSettle();
    expect(find.text('2024年2月'), findsOneWidget);
    expect(_day('2024-02-29'), findsOneWidget);
    expect(_day('2024-02-30'), findsNothing);

    for (var month = 0; month < 12; month++) {
      await tester.tap(_previousMonth);
      await tester.pumpAndSettle();
    }
    expect(find.text('2023年2月'), findsOneWidget);
    expect(_day('2023-02-28'), findsOneWidget);
    expect(_day('2023-02-29'), findsNothing);
  });

  testWidgets('初始日期限制在1900年到今天之间，1900年一月不能继续往前', (tester) async {
    await _showCalendar(
      tester,
      repository,
      today: today,
      initialDate: DateTime(1899, 12, 31),
    );
    expect(find.text('1900年1月'), findsOneWidget);
    expect(tester.widget<IconButton>(_previousMonth).onPressed, isNull);
    expect(
      tester.widget<Semantics>(_day('1900-01-01')).properties.selected,
      isTrue,
    );

    // 中文 Material 返回按钮的提示不是英文 Back，直接使用实际按钮类型。
    // 重建新的页面实例，检查来自外部的未来日期也会被归到今天。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _showCalendar(
      tester,
      repository,
      today: today,
      initialDate: DateTime(2025),
    );
    expect(find.text('2024年3月'), findsOneWidget);
    expect(
      tester.widget<Semantics>(_day('2024-03-15')).properties.selected,
      isTrue,
    );
  });

  testWidgets('回到今天定位今天和当前月份，仍停留在月历', (tester) async {
    final result = await _showCalendar(
      tester,
      repository,
      today: today,
      initialDate: DateTime(2023, 12, 4),
    );
    await tester.tap(find.byKey(const Key('calendar-today-button')));
    await tester.pumpAndSettle();

    expect(find.text('2024年3月'), findsOneWidget);
    expect(
      tester.widget<Semantics>(_day('2024-03-15')).properties.selected,
      isTrue,
    );
    expect(result.date, isNull);
    expect(find.byType(DreamCalendarPage), findsOneWidget);
  });

  testWidgets('切换月份时旧圆点清除，等待新月份数据后才显示新圆点', (tester) async {
    repository.setDates(DateTime(2024, 3), {'2024-03-05'});
    repository.waitForDates(DateTime(2024, 2));
    await _showCalendar(tester, repository, today: today);
    expect(find.byKey(const Key('calendar-marker-2024-03-05')), findsOneWidget);

    await tester.tap(_previousMonth);
    await tester.pumpAndSettle();
    expect(find.text('正在读取本月记录…'), findsOneWidget);
    expect(find.byKey(const Key('calendar-marker-2024-03-05')), findsNothing);
    expect(find.byKey(const Key('calendar-marker-2024-02-05')), findsNothing);
    expect(
      tester.widget<Semantics>(_day('2024-02-05')).properties.label,
      contains('记录状态暂不可用'),
    );

    repository.setDates(DateTime(2024, 2), {'2024-02-29'});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-marker-2024-02-29')), findsOneWidget);
    expect(find.text('正在读取本月记录…'), findsNothing);
  });

  testWidgets('订阅实时更新，新增和删除记录都会更新圆点', (tester) async {
    await _showCalendar(tester, repository, today: today);
    expect(find.text('本月还没有梦境记录，点击日期开始记录。'), findsOneWidget);

    repository.setDates(DateTime(2024, 3), {'2024-03-10'});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-marker-2024-03-10')), findsOneWidget);

    repository.setDates(DateTime(2024, 3), {});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-marker-2024-03-10')), findsNothing);
    expect(find.text('本月还没有梦境记录，点击日期开始记录。'), findsOneWidget);
  });

  testWidgets('读失败显示错误而非空记录，重试成功后恢复标记', (tester) async {
    repository.failNextRead(DateTime(2024, 3));
    await _showCalendar(tester, repository, today: today);
    expect(find.text('读取本月记录失败，记录标记暂不可用。'), findsOneWidget);
    expect(find.text('本月还没有梦境记录，点击日期开始记录。'), findsNothing);
    expect(
      tester.widget<Semantics>(_day('2024-03-05')).properties.label,
      contains('记录状态暂不可用'),
    );

    repository.setDates(DateTime(2024, 3), {'2024-03-05'});
    // 三月占六周，默认测试窗口需要先滚动才能真正点到日历下方的重试。
    final retry = find.byKey(const Key('calendar-retry-button'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(repository.reads['2024-3'], 2);
    expect(find.byKey(const Key('calendar-marker-2024-03-05')), findsOneWidget);
    expect(find.text('读取本月记录失败，记录标记暂不可用。'), findsNothing);
  });

  testWidgets('实时订阅出错会隐藏缓存圆点，重试后重新读取', (tester) async {
    repository.setDates(DateTime(2024, 3), {'2024-03-05'});
    await _showCalendar(tester, repository, today: today);
    repository.emitError(DateTime(2024, 3));
    await tester.pumpAndSettle();
    expect(find.text('读取本月记录失败，记录标记暂不可用。'), findsOneWidget);
    expect(find.byKey(const Key('calendar-marker-2024-03-05')), findsNothing);

    final retry = find.byKey(const Key('calendar-retry-button'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repository.reads['2024-3'], 2);
    expect(find.byKey(const Key('calendar-marker-2024-03-05')), findsOneWidget);
  });

  testWidgets('系统日期选择器取消留在月历，确认后返回所选日期', (tester) async {
    final result = await _showCalendar(tester, repository, today: today);
    final jump = find.byKey(const Key('calendar-jump-date-button'));
    await tester.tap(jump);
    await tester.pumpAndSettle();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.firstDate, DateTime(1900));
    expect(dialog.lastDate, today);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result.date, isNull);
    expect(find.byType(DreamCalendarPage), findsOneWidget);

    await tester.tap(jump);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result.date, today);
    expect(find.byType(DreamCalendarPage), findsNothing);
  });

  testWidgets('窄屏和大字号无溢出，可滚动查看月底及错误重试', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.failNextRead(DateTime(2024, 3));
    await _showCalendar(tester, repository, today: today, textScale: 2);
    expect(tester.takeException(), isNull);

    final retry = find.byKey(const Key('calendar-retry-button'));
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('读取本月记录失败，记录标记暂不可用。'), findsNothing);
  });
}

final _previousMonth = find.byKey(const Key('calendar-previous-month'));
final _nextMonth = find.byKey(const Key('calendar-next-month'));
Finder _day(String key) => find.byKey(Key('calendar-day-$key'));

class _SelectionResult {
  DateTime? date;
}

/// 从真实 Navigator 推入月历，测试返回值而不是仅验证点击回调。
Future<_SelectionResult> _showCalendar(
  WidgetTester tester,
  _CalendarRepository repository, {
  required DateTime today,
  DateTime? initialDate,
  double textScale = 1,
}) async {
  final result = _SelectionResult();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('launch-calendar'),
              onPressed: () async {
                result.date = await Navigator.push<DateTime>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DreamCalendarPage(
                      initialDate: initialDate ?? today,
                      now: () => today,
                    ),
                  ),
                );
              },
              child: const Text('打开月历'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('launch-calendar')));
  await tester.pumpAndSettle();
  return result;
}

/// 每个月有独立可控制的流，验证切换月份不会沿用旧月份的异步状态。
class _CalendarRepository implements ICalendarRepository {
  final _values = <String, Set<String>>{};
  final _waiting = <String>{};
  final _failures = <String>{};
  final _controllers = <String, StreamController<Set<String>>>{};
  final reads = <String, int>{};

  String _key(DateTime month) => '${month.year}-${month.month}';

  StreamController<Set<String>> _controller(String key) =>
      _controllers.putIfAbsent(key, () => StreamController.broadcast());

  void setDates(DateTime month, Set<String> dates) {
    final key = _key(month);
    _waiting.remove(key);
    _values[key] = Set.unmodifiable(dates);
    _controller(key).add(_values[key]!);
  }

  void waitForDates(DateTime month) => _waiting.add(_key(month));
  void failNextRead(DateTime month) => _failures.add(_key(month));
  void emitError(DateTime month) =>
      _controller(_key(month)).addError(StateError('模拟订阅中断'));

  @override
  Stream<Set<String>> watchRecordedDatesInMonth(DateTime month) async* {
    final key = _key(month);
    reads.update(key, (value) => value + 1, ifAbsent: () => 1);
    if (_failures.remove(key)) throw StateError('模拟读取失败');
    if (!_waiting.contains(key)) yield _values[key] ?? <String>{};
    yield* _controller(key).stream;
  }

  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
