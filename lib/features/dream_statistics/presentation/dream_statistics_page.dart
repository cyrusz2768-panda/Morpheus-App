import 'dart:async';
import 'dart:math' as math;

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
  const DreamStatisticsPage({super.key, this.now});
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
    _anchor = _today;
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
    final datesProvider = statisticsDatesProvider(window);
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
                    data: (keys) => _StatisticsContent(
                      stats: DreamStatistics(
                        window: window,
                        dateKeys: keys,
                        today: _today,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.statisticsDateNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
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

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({required this.stats});
  final DreamStatistics stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final difference = stats.recordedDays - stats.previousRecordedDays;
    final comparison = context.l10n.statisticsComparison(
      difference > 0
          ? 'more'
          : difference < 0
          ? 'less'
          : 'equal',
      difference.abs(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          color: colors.primaryContainer.withValues(alpha: .45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.statisticsRecordedDaysLabel),
              const SizedBox(height: 6),
              Text(
                context.l10n.statisticsDayCount(stats.recordedDays),
                key: const Key('statistics-recorded-days'),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(comparison, key: const Key('statistics-comparison')),
              const SizedBox(height: 14),
              Text(
                context.l10n.statisticsCoverageSummary(
                  (stats.coverage * 100).toStringAsFixed(0),
                  stats.elapsedDays,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: stats.coverage,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.statisticsComparisonNote,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.statisticsTrendTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.statisticsTrendDescription(
                  stats.window.period.name,
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              _TrendChart(stats: stats),
              if (stats.recordedDays == 0) ...[
                const SizedBox(height: 16),
                Text(
                  context.l10n.statisticsEmpty,
                  key: const Key('statistics-empty'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.statisticsDayTypeTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.statisticsShareDescription,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              _ShareRow(
                label: context.l10n.statisticsWeekend,
                days: stats.weekendDays,
                ratio: stats.recordedDays == 0 ? null : stats.weekendShare,
                displayPercent: (100 * stats.weekendShare).round(),
                color: colors.primary,
              ),
              const SizedBox(height: 16),
              _ShareRow(
                label: context.l10n.statisticsWeekday,
                days: stats.weekdayDays,
                ratio: stats.recordedDays == 0 ? null : 1 - stats.weekendShare,
                // 显示取互补整数，避免两个比例分别舍入后合计101%。
                displayPercent: 100 - (100 * stats.weekendShare).round(),
                color: colors.tertiary,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.statisticsDayTypeNote,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.stats});
  final DreamStatistics stats;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maximum = stats.buckets.fold<int>(
      1,
      (value, bucket) => math.max(value, bucket.recordedDays),
    );
    // 年视图十二列在窄屏/大字号下可横向滚动；每根柱同时有可读数值和
    // 完整日期读屏标签，不靠颜色或图形传达唯一信息。
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final width = math.max(
          constraints.maxWidth,
          stats.buckets.length * 44.0 * scale,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final bucket in stats.buckets)
                  Expanded(
                    child: Semantics(
                      label: context.l10n.statisticsBucketSemantics(
                        _date(context.l10n, bucket.start),
                        _date(
                          context.l10n,
                          DateTime(
                            bucket.end.year,
                            bucket.end.month,
                            bucket.end.day - 1,
                          ),
                        ),
                        (bucket.elapsedDays == 0).toString(),
                        bucket.recordedDays,
                      ),
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          Text(
                            context.l10n.statisticsBucketCount(
                              (bucket.elapsedDays == 0).toString(),
                              bucket.recordedDays,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 100,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 18,
                                height: bucket.recordedDays == 0
                                    ? 3
                                    : 100 * bucket.recordedDays / maximum,
                                decoration: BoxDecoration(
                                  color: bucket.elapsedDays == 0
                                      ? colors.outlineVariant
                                      : bucket.recordedDays == 0
                                      ? colors.primaryContainer
                                      : colors.primary,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(switch (stats.window.period) {
                            StatisticsPeriod.week => context.l10n.weekdayShort(
                              bucket.start.weekday.toString(),
                            ),
                            StatisticsPeriod.month =>
                              context.l10n.statisticsDayRange(
                                bucket.start.day,
                                DateTime(
                                  bucket.end.year,
                                  bucket.end.month,
                                  bucket.end.day - 1,
                                ).day,
                              ),
                            StatisticsPeriod.year =>
                              context.l10n.statisticsMonthTick(
                                bucket.start.month,
                              ),
                          }, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.label,
    required this.days,
    required this.ratio,
    required this.displayPercent,
    required this.color,
  });
  final String label;
  final int days;
  final double? ratio;
  final int displayPercent;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            context.l10n.statisticsShareSummary(
              days,
              (ratio != null).toString(),
              displayPercent,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: ratio ?? 0,
        color: color,
        minHeight: 6,
        borderRadius: BorderRadius.circular(4),
      ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    color: color ?? Theme.of(context).colorScheme.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

String _date(AppLocalizations l10n, DateTime date) =>
    l10n.statisticsDate(date.year, date.month, date.day);
