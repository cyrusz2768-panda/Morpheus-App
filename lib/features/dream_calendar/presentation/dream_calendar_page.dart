import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_calendar/application/recorded_dream_dates_provider.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// 月历只负责选择日期，正文的读取、修改和保存继续交给原来的编辑器。
///
/// 注入时钟后，今天、未来日期和跨年边界都可以在测试中固定下来。
class DreamCalendarPage extends ConsumerStatefulWidget {
  const DreamCalendarPage({super.key, required this.initialDate, this.now});

  final DateTime initialDate;
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
      helpText: '选择梦境日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (mounted && selected != null) {
      Navigator.pop<DateTime>(context, selected);
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
      appBar: AppBar(title: const Text('梦境月历')),
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
                  const Text('选择日期，查看或记录当天的梦境。'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('calendar-today-button'),
                        onPressed: _returnToToday,
                        icon: const Icon(Icons.today_outlined),
                        label: const Text('回到今天'),
                      ),
                      TextButton.icon(
                        key: const Key('calendar-jump-date-button'),
                        onPressed: _jumpToDate,
                        icon: const Icon(Icons.date_range_outlined),
                        label: const Text('选择日期'),
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
                                tooltip: '上个月',
                                onPressed: _focusedMonth.isAfter(_firstDate)
                                    ? () => _moveMonth(-1)
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: Text(
                                  '${_focusedMonth.year}年${_focusedMonth.month}月',
                                  key: const Key('calendar-month-label'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              IconButton(
                                key: const Key('calendar-next-month'),
                                tooltip: '下个月',
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
                              for (final weekday in const [
                                '一',
                                '二',
                                '三',
                                '四',
                                '五',
                                '六',
                                '日',
                              ])
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      weekday,
                                      style: theme.textTheme.labelLarge,
                                      semanticsLabel: '星期$weekday',
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
                      const Expanded(child: Text('有梦境记录')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  recordedDates.when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    loading: () => Semantics(
                      liveRegion: true,
                      child: const Text('正在读取本月记录…'),
                    ),
                    error: (error, stackTrace) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '读取本月记录失败，记录标记暂不可用。',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        TextButton.icon(
                          key: const Key('calendar-retry-button'),
                          onPressed: () => ref.invalidate(monthProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                    data: (dates) => dates.isEmpty
                        ? const Text('本月还没有梦境记录，点击日期开始记录。')
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
        ? '记录状态暂不可用'
        : hasRecord
        ? '有梦境记录'
        : '无梦境记录';

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        key: Key('calendar-day-$dateKey'),
        label:
            '${date.year}年${date.month}月${date.day}日'
            '${isToday ? '，今天' : ''}，$recordLabel'
            '${enabled ? '' : '，未来日期不可选择'}',
        button: true,
        enabled: enabled,
        selected: selected,
        onTap: enabled ? () => Navigator.pop<DateTime>(context, date) : null,
        excludeSemantics: true,
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isToday ? BorderSide(color: colors.primary) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled
                ? () => Navigator.pop<DateTime>(context, date)
                : null,
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
