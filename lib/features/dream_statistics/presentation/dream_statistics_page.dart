import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/app/main_bottom_navigation.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_statistics/application/statistics_provider.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

/// 本轮按用户要求先验收中文界面，新增文字在验收通过后统一接入 ARB。
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
      StatisticsPeriod.week => '${_date(window.start)} — ${_date(last)}',
      StatisticsPeriod.month => '${window.start.year}年${window.start.month}月',
      StatisticsPeriod.year => '${window.start.year}年',
    };

    return Scaffold(
      bottomNavigationBar: const MainBottomNavigation(selectedIndex: 1),
      appBar: AppBar(title: const Text('梦境统计')),
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
                    segments: const [
                      ButtonSegment(
                        value: StatisticsPeriod.week,
                        label: Text('周'),
                      ),
                      ButtonSegment(
                        value: StatisticsPeriod.month,
                        label: Text('月'),
                      ),
                      ButtonSegment(
                        value: StatisticsPeriod.year,
                        label: Text('年'),
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
                        tooltip: '上一周期',
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
                        tooltip: '下一周期',
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
                      label: Text(switch (_period) {
                        StatisticsPeriod.week => '回到本周',
                        StatisticsPeriod.month => '回到本月',
                        StatisticsPeriod.year => '回到本年',
                      }),
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
                          const Text('统计读取失败，请重试。'),
                          TextButton(
                            key: const Key('statistics-retry'),
                            onPressed: () => ref.invalidate(datesProvider),
                            child: const Text('重试'),
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
                    '按梦境所属日期统计，每天最多计一次。补记、修改与删除会自动更新。',
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
    final comparison = difference == 0
        ? '与上期持平'
        : '较上期${difference > 0 ? '多' : '少'} ${difference.abs()} 天';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          color: colors.primaryContainer.withValues(alpha: .45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('记录天数'),
              const SizedBox(height: 6),
              Text(
                '${stats.recordedDays} 天',
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
                '记录覆盖率 ${_percent(stats.coverage)} · 已经过 ${stats.elapsedDays} 天',
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: stats.coverage,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 10),
              Text(
                '当前周期只计截至今天的日期，并与上期相同天数比较；上期较短时取全期。历史周期比较完整周期。',
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
              Text('记录趋势', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(switch (stats.window.period) {
                StatisticsPeriod.week => '每天是否留下梦境记录',
                StatisticsPeriod.month => '按周汇总记录天数，首尾按本月裁切',
                StatisticsPeriod.year => '每月的记录天数',
              }, style: theme.textTheme.bodySmall),
              const SizedBox(height: 20),
              _TrendChart(stats: stats),
              if (stats.recordedDays == 0) ...[
                const SizedBox(height: 16),
                const Text(
                  '这个周期还没有记录。记下一个梦，回顾就从这里开始。',
                  key: Key('statistics-empty'),
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
              Text('周末 / 平日', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('占本周期记录天数的比例', style: theme.textTheme.bodySmall),
              const SizedBox(height: 18),
              _ShareRow(
                label: '双休日',
                days: stats.weekendDays,
                ratio: stats.recordedDays == 0 ? null : stats.weekendShare,
                displayPercent: (100 * stats.weekendShare).round(),
                color: colors.primary,
              ),
              const SizedBox(height: 16),
              _ShareRow(
                label: '平日',
                days: stats.weekdayDays,
                ratio: stats.recordedDays == 0 ? null : 1 - stats.weekendShare,
                // 显示取互补整数，避免两个比例分别舍入后合计101%。
                displayPercent: 100 - (100 * stats.weekendShare).round(),
                color: colors.tertiary,
              ),
              const SizedBox(height: 16),
              Text(
                '双休日为周六、周日；平日为周一至周五，不按法定节假日或调休调整。',
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
                      label:
                          '${_date(bucket.start)}至${_date(DateTime(bucket.end.year, bucket.end.month, bucket.end.day - 1))}，${bucket.elapsedDays == 0 ? '尚未开始' : '记录${bucket.recordedDays}天'}',
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          Text(
                            bucket.elapsedDays == 0
                                ? '—'
                                : '${bucket.recordedDays}',
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
                            StatisticsPeriod.week => [
                              '一',
                              '二',
                              '三',
                              '四',
                              '五',
                              '六',
                              '日',
                            ][bucket.start.weekday - 1],
                            StatisticsPeriod.month =>
                              '${bucket.start.day}–${DateTime(bucket.end.year, bucket.end.month, bucket.end.day - 1).day}',
                            StatisticsPeriod.year => '${bucket.start.month}月',
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
          Text('$days 天 · ${ratio == null ? '—' : '$displayPercent%'}'),
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

String _date(DateTime date) => '${date.year}.${date.month}.${date.day}';
String _percent(double value) => '${(value * 100).toStringAsFixed(0)}%';
