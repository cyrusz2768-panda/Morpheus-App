import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';
import 'package:morpheus/features/dream_statistics/presentation/feedback_statistics_content.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/app/main_bottom_navigation.dart';
import 'package:morpheus/l10n/app_text.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_statistics/application/statistics_provider.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

/// 页面通过 context.l10n 读取文案；日期、整句数量提示与读屏标签均由资源
/// 组合占位符，业务层只提供数据，避免页面拼接中文影响未来的语序调整。
/// 页面只持有浏览的周期；数据库监听、聚合与编辑器保存各有独立职责。
class DreamStatisticsPage extends ConsumerStatefulWidget {
  const DreamStatisticsPage({super.key, this.now, this.initialDate});
  final DateTime? initialDate;
  final DateTime Function()? now;

  @override
  ConsumerState<DreamStatisticsPage> createState() =>
      _DreamStatisticsPageState();
}

class _DreamStatisticsPageState extends ConsumerState<DreamStatisticsPage>
    with WidgetsBindingObserver {
  StatisticsPeriod _period = StatisticsPeriod.week;
  late DateTime _anchor;
  Timer? _dayTimer;

  DateTime get _today =>
      DreamEntry.dateOnly(widget.now?.call() ?? DateTime.now());
  StatisticsWindow get _window => StatisticsWindow(_period, _anchor);

  @override
  void initState() {
    super.initState();
    _anchor = widget.initialDate ?? _today;
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextDay();
  }

  void _scheduleNextDay() {
    _dayTimer?.cancel();
    if (widget.now != null) return;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(tomorrow.difference(now), () {
      if (mounted) setState(() {});
      _scheduleNextDay();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台返回也更新“截至今天”的分母，不依赖后台计时器准时运行。
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _scheduleNextDay();
    }
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _move(int offset) =>
      setState(() => _anchor = _window.move(offset).start);

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final current = StatisticsWindow(_period, _today);
    final datesProvider = statisticsRecordsProvider(window);
    final dates = ref.watch(datesProvider);
    final colors = Theme.of(context).colorScheme;
    final last = DateTime(
      window.end.year,
      window.end.month,
      window.end.day - 1,
    );
    final title = switch (_period) {
      StatisticsPeriod.week => context.l10n.statisticsWeekRange(
        _date(context.l10n, window.start),
        _date(context.l10n, last),
      ),
      StatisticsPeriod.month => context.l10n.calendarMonth(
        window.start.year,
        window.start.month,
      ),
      StatisticsPeriod.year => context.l10n.statisticsYear(window.start.year),
    };

    return Scaffold(
      bottomNavigationBar: const MainBottomNavigation(selectedIndex: 1),
      appBar: AppBar(title: Text(context.l10n.statisticsTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<StatisticsPeriod>(
                    key: const Key('statistics-period-control'),
                    segments: [
                      ButtonSegment(
                        value: StatisticsPeriod.week,
                        label: Text(context.l10n.statisticsPeriodLabel('week')),
                      ),
                      ButtonSegment(
                        value: StatisticsPeriod.month,
                        label: Text(
                          context.l10n.statisticsPeriodLabel('month'),
                        ),
                      ),
                      ButtonSegment(
                        value: StatisticsPeriod.year,
                        label: Text(context.l10n.statisticsPeriodLabel('year')),
                      ),
                    ],
                    selected: {_period},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => setState(() {
                      _period = selection.single;
                      // 周可能跨月/跨年，保留浏览焦点而不是取周一所属月份。
                    }),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('statistics-previous'),
                        tooltip: context.l10n.statisticsPreviousPeriod,
                        onPressed: window.start.isAfter(DateTime(1900, 1, 1))
                            ? () => _move(-1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          key: const Key('statistics-range'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        key: const Key('statistics-next'),
                        tooltip: context.l10n.statisticsNextPeriod,
                        onPressed: window.start.isBefore(current.start)
                            ? () => _move(1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      key: const Key('statistics-current'),
                      onPressed: window == current
                          ? null
                          : () => setState(() => _anchor = _today),
                      icon: const Icon(Icons.today_outlined, size: 18),
                      label: Text(
                        context.l10n.statisticsBackToCurrent(_period.name),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 切期和重试时不显示旧结果；故障也不冒充零记录。
                  dates.when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    loading: () => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, stackTrace) => _Panel(
                      child: Column(
                        children: [
                          Icon(Icons.cloud_off_outlined, color: colors.error),
                          const SizedBox(height: 12),
                          Text(context.l10n.statisticsLoadFailed),
                          TextButton(
                            key: const Key('statistics-retry'),
                            onPressed: () => ref.invalidate(datesProvider),
                            child: Text(context.l10n.retry),
                          ),
                        ],
                      ),
                    ),
                    data: (records) => FeedbackStatisticsContent(
                      statistics: SleepFeedbackStatistics(
                        window: window,
                        records: records,
                        today: _today,
                      ),
                      isCurrent: current == window,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

String _date(AppLocalizations l10n, DateTime date) =>
    l10n.statisticsDate(date.year, date.month, date.day);
