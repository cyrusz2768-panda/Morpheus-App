import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:morpheus/app/main_bottom_navigation.dart';
import 'package:morpheus/l10n/app_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_calendar/application/recorded_dream_dates_provider.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// 月历只负责选择日期，正文的读取、修改和保存继续交给原来的编辑器。
///
/// 注入时钟后，今天、未来日期和跨年边界都可以在测试中固定下来。
class DreamCalendarPage extends ConsumerStatefulWidget {
  const DreamCalendarPage({
    super.key,
    required this.initialDate,
    this.now,
    this.onDateSelected,
  });

  final DateTime initialDate;
  // 顶级日历回调选日；旧全屏选日器仍通过 pop 返回日期。
  final ValueChanged<DateTime>? onDateSelected;
  final DateTime Function()? now;

  @override
  ConsumerState<DreamCalendarPage> createState() => _DreamCalendarPageState();
}

class _DreamCalendarPageState extends ConsumerState<DreamCalendarPage> {
  static final _firstDate = DateTime(1900);
  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  DateTime get _today =>
      DreamEntry.dateOnly(widget.now?.call() ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _selectedDate = _clampDate(widget.initialDate);
    _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  DateTime _clampDate(DateTime date) {
    final day = DreamEntry.dateOnly(date);
    if (day.isBefore(_firstDate)) return _firstDate;
    if (day.isAfter(_today)) return _today;
    return day;
  }

  void _moveMonth(int offset) {
    final target = DateTime(_focusedMonth.year, _focusedMonth.month + offset);
    final lastMonth = DateTime(_today.year, _today.month);
    if (target.isBefore(_firstDate) || target.isAfter(lastMonth)) return;
    setState(() => _focusedMonth = target);
  }

  void _returnToToday() {
    final today = _today;
    setState(() {
      _selectedDate = today;
      _focusedMonth = DateTime(today.year, today.month);
    });
  }

  Future<void> _jumpToDate() async {
    // 保留系统选择器方便跨很多年跳转；取消时不改变当前月历或编辑日期。
    final selected = await showDatePicker(
      context: context,
      initialDate: _clampDate(_selectedDate),
      firstDate: _firstDate,
      lastDate: _today,
      currentDate: _today,
      helpText: context.l10n.selectDreamDate,
      cancelText: context.l10n.cancel,
      confirmText: context.l10n.confirm,
    );
    if (mounted && selected != null) {
      _selectDate(selected);
    }
  }

  void _selectDate(DateTime date) {
    if (widget.onDateSelected case final callback?) {
      callback(date);
    } else {
      Navigator.pop<DateTime>(context, date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _today;
    final lastMonth = DateTime(today.year, today.month);
    final monthProvider = recordedDreamDatesProvider(_focusedMonth);
    final recordedDates = ref.watch(monthProvider);

    // 加载、刷新和失败都表示“记录状态未知”。不要把缓存或上个月的点当作
    // 当前月结果，也不要在读取失败时向用户断言本月没有梦境。
    final dates = recordedDates.when<Set<String>?>(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      data: (value) => value,
      loading: () => null,
      error: (error, stackTrace) => null,
    );

    return Scaffold(
      bottomNavigationBar: widget.onDateSelected == null
          ? null
          : const MainBottomNavigation(selectedIndex: 2),
      appBar: AppBar(title: Text(context.l10n.dreamCalendar)),
      body: SafeArea(
        // 滚动容器应对小屏和大字号；宽屏限宽，避免七列日期相距太远。
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.l10n.calendarPrompt),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('calendar-today-button'),
                        onPressed: _returnToToday,
                        icon: const Icon(Icons.today_outlined),
                        label: Text(context.l10n.backToToday),
                      ),
                      TextButton.icon(
                        key: const Key('calendar-jump-date-button'),
                        onPressed: _jumpToDate,
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text(context.l10n.selectDate),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                key: const Key('calendar-previous-month'),
                                tooltip: context.l10n.previousMonth,
                                onPressed: _focusedMonth.isAfter(_firstDate)
                                    ? () => _moveMonth(-1)
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: Text(
                                  context.l10n.calendarMonth(
                                    _focusedMonth.year,
                                    _focusedMonth.month,
                                  ),
                                  key: const Key('calendar-month-label'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              IconButton(
                                key: const Key('calendar-next-month'),
                                tooltip: context.l10n.nextMonth,
                                onPressed: _focusedMonth.isBefore(lastMonth)
                                    ? () => _moveMonth(1)
                                    : null,
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (
                                var weekday = DateTime.monday;
                                weekday <= DateTime.sunday;
                                weekday++
                              )
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      context.l10n.weekdayShort('$weekday'),
                                      style: theme.textTheme.labelLarge,
                                      semanticsLabel: context.l10n.weekdayLabel(
                                        '$weekday',
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildDays(context, today, dates),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(context.l10n.hasDreamRecord)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  recordedDates.when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    loading: () => Semantics(
                      liveRegion: true,
                      child: Text(context.l10n.calendarLoading),
                    ),
                    error: (error, stackTrace) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.calendarLoadFailed,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        TextButton.icon(
                          key: const Key('calendar-retry-button'),
                          onPressed: () => ref.invalidate(monthProvider),
                          icon: const Icon(Icons.refresh),
                          label: Text(context.l10n.retry),
                        ),
                      ],
                    ),
                    data: (dates) => dates.isEmpty
                        ? Text(context.l10n.calendarEmpty)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDays(
    BuildContext context,
    DateTime today,
    Set<String>? recordedDates,
  ) {
    final leadingDays = _focusedMonth.weekday - DateTime.monday;
    final dayCount = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;
    final weekCount = (leadingDays + dayCount + 6) ~/ 7;
    // 只把字号换算成所需行高，不限制系统文字缩放；日期数字可在窄列中缩小。
    final cellHeight = math.max(
      52.0,
      MediaQuery.textScalerOf(context).scale(18) + 30,
    );

    return Column(
      children: [
        for (var week = 0; week < weekCount; week++)
          Row(
            children: [
              for (var weekday = 0; weekday < 7; weekday++)
                Expanded(
                  child: SizedBox(
                    height: cellHeight,
                    child: _buildCell(
                      context,
                      week * 7 + weekday - leadingDays + 1,
                      dayCount,
                      today,
                      recordedDates,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCell(
    BuildContext context,
    int day,
    int dayCount,
    DateTime today,
    Set<String>? recordedDates,
  ) {
    // 月首、月尾留白，不显示邻月日期，避免跨月标记与点击含义混淆。
    if (day < 1 || day > dayCount) return const SizedBox.shrink();
    final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
    final dateKey = DreamEntry.dateKey(date);
    final enabled = !date.isBefore(_firstDate) && !date.isAfter(today);
    final isToday = date == today;
    final selected = date == _selectedDate;
    final hasRecord = recordedDates?.contains(dateKey) ?? false;
    final colors = Theme.of(context).colorScheme;
    final recordLabel = recordedDates == null
        ? context.l10n.recordStatusUnavailable
        : hasRecord
        ? context.l10n.hasDreamRecord
        : context.l10n.noDreamRecord;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        key: Key('calendar-day-$dateKey'),
        label: context.l10n.calendarDayLabel(
          context.l10n.dreamDate(date.year, date.month, date.day),
          isToday.toString(),
          recordLabel,
          enabled.toString(),
        ),
        button: true,
        enabled: enabled,
        selected: selected,
        onTap: enabled ? () => _selectDate(date) : null,
        excludeSemantics: true,
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isToday ? BorderSide(color: colors.primary) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? () => _selectDate(date) : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$day',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: isToday ? FontWeight.bold : null,
                          color: enabled
                              ? selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface
                              : colors.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // 空位置也占相同高度，确保有记录与无记录的数字始终对齐。
                SizedBox(
                  height: 6,
                  width: 6,
                  child: hasRecord
                      ? DecoratedBox(
                          key: Key('calendar-marker-$dateKey'),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
