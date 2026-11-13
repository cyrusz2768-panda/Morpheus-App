import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:morpheus/features/dream_editor/presentation/daily_feedback_text.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';
import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';
import 'package:morpheus/l10n/app_text.dart';

/// 普通统计与每周回顾使用同一组卡片。这里接收已聚合快照，不读取数据库，
/// 不展示记录天数或状态次数；颜色、图例和比例共同解释状态分布。
class FeedbackStatisticsContent extends StatelessWidget {
  const FeedbackStatisticsContent({
    super.key,
    required this.statistics,
    required this.isCurrent,
  });
  final SleepFeedbackStatistics statistics;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scope = l.statisticsReviewScope(
      statistics.activity.window.period.name,
      isCurrent.toString(),
    );
    final average = statistics.averageScore;
    final isWeek = statistics.activity.window.period == StatisticsPeriod.week;
    final hasUncertain = statistics.topFactors.contains(SleepFactor.unsure);
    final factors = statistics.topFactors
        .where((factor) => factor != SleepFactor.unsure)
        .map((f) => factorLabel(context, f))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.statisticsMoodTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                l.statisticsMoodInsight(scope, statistics.moodInsight.name),
                key: const Key('statistics-mood-insight'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 24),
              if (isWeek)
                _WeekStatusGrid(statistics: statistics)
              else ...[
                Center(
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: CustomPaint(
                      key: const Key('statistics-status-chart'),
                      painter: StatusRingPainter(
                        counts: statistics.statusCounts,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    for (final category in DreamStatusCategory.values)
                      Semantics(
                        label: l.statisticsStatusSemantics(
                          l.statisticsStatusLabel(category.name),
                          statistics.activity.elapsedDays == 0
                              ? l.statisticsUnknownValue
                              : (100 *
                                        statistics.statusCounts[category]! /
                                        statistics.activity.elapsedDays)
                                    .toStringAsFixed(0),
                          (statistics.activity.elapsedDays > 0).toString(),
                        ),
                        excludeSemantics: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              key: Key('statistics-status-${category.name}'),
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: statusColor(category),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(l.statisticsStatusLabel(category.name)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              if (statistics.goodShare != null) ...[
                const SizedBox(height: 18),
                Text(
                  l.statisticsDreamRatio(
                    (100 * statistics.goodShare!).round(),
                    100 - (100 * statistics.goodShare!).round(),
                  ),
                  key: const Key('statistics-dream-ratio'),
                ),
              ],
              const SizedBox(height: 12),
              _Note(l.statisticsDreamRatioNote),
              const SizedBox(height: 6),
              _Note(
                isWeek
                    ? l.statisticsWeekMoodChartNote
                    : l.statisticsMoodChartNote,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.statisticsScoreTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(l.statisticsAverageScoreLabel),
              Text(
                average == null
                    ? l.statisticsUnknownValue
                    : l.statisticsAverageScore(average.toStringAsFixed(1)),
                key: const Key('statistics-score-average'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (average == null) Text(l.statisticsScoreEmpty),
              const SizedBox(height: 24),
              Text(
                l.statisticsScoreTrendTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              _Note(
                l.statisticsScoreTrendNote(
                  statistics.activity.window.period.name,
                ),
              ),
              const SizedBox(height: 16),
              _ScoreTrend(statistics: statistics),
              const SizedBox(height: 12),
              _Note(l.statisticsScoreNote),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.statisticsFactorsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                hasUncertain
                    ? l.statisticsFactorsUncertainSummary(
                        scope,
                        factors.length,
                        factors.elementAtOrNull(0) ?? '',
                        factors.elementAtOrNull(1) ?? '',
                      )
                    : l.statisticsFactorsSummary(
                        scope,
                        factors.length,
                        factors.elementAtOrNull(0) ?? '',
                        factors.elementAtOrNull(1) ?? '',
                        factors.elementAtOrNull(2) ?? '',
                      ),
                key: const Key('statistics-factors-summary'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              _Note(l.statisticsFactorsNote),
            ],
          ),
        ),
      ],
    );
  }
}

/// 固定五种语义颜色：好梦黄、噩梦紫、忘记浅棕、没做梦蓝灰、未填灰。
Color statusColor(DreamStatusCategory category) => switch (category) {
  DreamStatusCategory.good => const Color(0xFFE8BE45),
  DreamStatusCategory.nightmare => const Color(0xFF8070B4),
  DreamStatusCategory.forgotten => const Color(0xFFCDB69D),
  DreamStatusCategory.noDream => const Color(0xFF8EABB8),
  DreamStatusCategory.unfilled => const Color(0xFFD9D9DF),
};

class StatusRingPainter extends CustomPainter {
  StatusRingPainter({required this.counts});
  final Map<DreamStatusCategory, int> counts;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(18, 18, size.width - 36, size.height - 36);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;
    final total = counts.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        paint..color = statusColor(DreamStatusCategory.unfilled),
      );
      return;
    }
    var start = -math.pi / 2;
    for (final category in DreamStatusCategory.values) {
      final sweep = math.pi * 2 * counts[category]! / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        paint..color = statusColor(category),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(StatusRingPainter old) => old.counts != counts;
}

/// 周状态按列表示星期、按行表示四种状态，每列最多只有一个着色格。
/// 行标签与星期标签保持可读；图内没有滚动层，也不把未填推断成没做梦。
class _WeekStatusGrid extends StatelessWidget {
  const _WeekStatusGrid({required this.statistics});
  final SleepFeedbackStatistics statistics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final l = context.l10n;
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      // 超过两倍的辅助字号也允许行高增长，避免三字状态名称换行后被裁切。
      // 只增加页面纵向高度，网格宽度始终受卡片约束，不产生横向滚动。
      final rowHeight = 42.0 * scale;
      final labelWidth = math.min(82.0 * scale, constraints.maxWidth * .3);
      return SizedBox(
        key: const Key('statistics-status-chart'),
        width: constraints.maxWidth,
        child: Row(
          key: const Key('statistics-week-status-grid'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    for (final mood in DreamMood.values)
                      SizedBox(
                        height: rowHeight,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            moodLabel(context, mood),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
            for (final day in statistics.weekDays)
              Expanded(
                child: Semantics(
                  label: l.statisticsWeekStatusSemantics(
                    _date(l, day.date),
                    l.weekdayShort(day.date.weekday.toString()),
                    day.isFuture
                        ? l.statisticsFutureScore
                        : moodLabel(context, day.mood),
                  ),
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      for (final mood in DreamMood.values)
                        Container(
                          key: Key(
                            'statistics-week-cell-${day.date.year}-${day.date.month}-${day.date.day}-${mood.name}',
                          ),
                          height: rowHeight - 6,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: day.mood == mood
                                ? statusColor(
                                    DreamStatusCategory.values.byName(
                                      mood.name,
                                    ),
                                  )
                                : Colors.transparent,
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: .6),
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      SizedBox(
                        height: 28,
                        child: Center(
                          child: _AxisLabel(
                            l.weekdayShort(day.date.weekday.toString()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _ScoreTrend extends StatelessWidget {
  const _ScoreTrend({required this.statistics});
  final SleepFeedbackStatistics statistics;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final l = context.l10n;
      final colors = Theme.of(context).colorScheme;
      // 画布始终使用当前卡片宽度，周7点、月4/5点、年12点均完整可见。
      // 去掉每列均分文字，避免12列在手机上互相挤压；纵轴固定1–5分，
      // 每个分组的完整日期和准确均分由读屏和长按刻度提示提供。
      return Column(
        key: const Key('statistics-score-plot'),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 172,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var score = 5; score >= 1; score--)
                        SizedBox(
                          height: 14,
                          child: _AxisLabel(l.statisticsScoreAxisLabel(score)),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 172,
                      width: double.infinity,
                      child: CustomPaint(
                        key: const Key('statistics-score-chart'),
                        painter: ScoreTrendPainter(
                          values: statistics.scoreBuckets
                              .map((b) => b.average)
                              .toList(),
                          color: colors.primary,
                          gridColor: colors.outlineVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final bucket in statistics.scoreBuckets)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final description = l
                                    .statisticsScoreBucketSemantics(
                                      _date(l, bucket.start),
                                      _date(
                                        l,
                                        DateTime(
                                          bucket.end.year,
                                          bucket.end.month,
                                          bucket.end.day - 1,
                                        ),
                                      ),
                                      bucket.isFuture
                                          ? l.statisticsFutureScore
                                          : bucket.average == null
                                          ? l.dailyUnfilled
                                          : l.statisticsAverageScore(
                                              bucket.average!.toStringAsFixed(
                                                1,
                                              ),
                                            ),
                                    );
                                final tick = switch (statistics
                                    .activity
                                    .window
                                    .period) {
                                  StatisticsPeriod.week => l.weekdayShort(
                                    bucket.start.weekday.toString(),
                                  ),
                                  StatisticsPeriod.month =>
                                    l.statisticsDayRange(
                                      bucket.start.day,
                                      DateTime(
                                        bucket.end.year,
                                        bucket.end.month,
                                        bucket.end.day - 1,
                                      ).day,
                                    ),
                                  StatisticsPeriod.year =>
                                    l.statisticsMonthTick(bucket.start.month),
                                };
                                return Semantics(
                                  label: description,
                                  excludeSemantics: true,
                                  child: Tooltip(
                                    message: description,
                                    excludeFromSemantics: true,
                                    child: SizedBox(
                                      height: 30,
                                      child: _AxisLabel(tick),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// 只缩放轴标注以适应有限列宽，不缩放图线或整张卡片。
/// 完整文本仍在语义和提示中提供，大字号下正文继续按系统设置排版。
class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

/// 固定1–5纵轴。null 留空并中断折线，既不补0，也不跨缺失分组连线。
/// 纵轴和日期刻度解释图线；准确均分通过长按刻度及读屏提供。
class ScoreTrendPainter extends CustomPainter {
  ScoreTrendPainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });
  final List<double?> values;
  final Color color;
  final Color gridColor;
  @override
  void paint(Canvas canvas, Size size) {
    const top = 14.0;
    final height = size.height - 28;
    for (var score = 1; score <= 5; score++) {
      final y = top + height * (5 - score) / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = gridColor.withValues(alpha: .5),
      );
    }
    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        previous = null;
        continue;
      }
      final point = Offset(
        size.width * (i + .5) / values.length,
        top + height * (5 - value) / 4,
      );
      if (previous != null) {
        canvas.drawLine(
          previous,
          point,
          Paint()
            ..color = color
            ..strokeWidth = 2.5,
        );
      }
      canvas.drawCircle(point, 4, Paint()..color = color);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(ScoreTrendPainter old) =>
      old.values != values || old.color != color || old.gridColor != gridColor;
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

String _date(AppLocalizations l, DateTime date) =>
    l.statisticsDate(date.year, date.month, date.day);
