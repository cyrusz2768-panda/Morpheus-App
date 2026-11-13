import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';
import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';

StatisticsRecord record(
  int day, {
  DreamMood? mood,
  int? score,
  Set<SleepFactor> factors = const {},
  bool content = false,
}) => StatisticsRecord(
  date: DateTime(2026, 11, day),
  hasContent: content,
  feedback: DailyFeedback(mood: mood, sleepScore: score, factors: factors),
);
SleepFeedbackStatistics stats(
  List<StatisticsRecord> records, {
  StatisticsPeriod period = StatisticsPeriod.week,
  DateTime? today,
}) => SleepFeedbackStatistics(
  window: StatisticsWindow(period, DateTime(2026, 11, 9)),
  records: records,
  today: today ?? DateTime(2026, 11, 15),
);

void main() {
  test('四状态与未填写分离，旧正文不推断状态，空日期不是没做梦', () {
    final result = stats([
      record(9, mood: DreamMood.good),
      record(10, mood: DreamMood.nightmare),
      record(11, mood: DreamMood.forgotten),
      record(12, mood: DreamMood.noDream),
      record(13, content: true),
      record(14),
    ]);
    expect(result.statusCounts, {
      DreamStatusCategory.good: 1,
      DreamStatusCategory.nightmare: 1,
      DreamStatusCategory.forgotten: 1,
      DreamStatusCategory.noDream: 1,
      DreamStatusCategory.unfilled: 3,
    });
    expect(result.activity.recordedDays, 1);
    expect(result.goodShare, .5);
    expect(result.averageScore, isNull);
  });
  test('只纳入本期截至今天，含上期与未来的投影不污染反馈', () {
    final result = stats([
      record(8, mood: DreamMood.good, score: 5),
      record(9, mood: DreamMood.noDream, score: 1),
      record(10, mood: DreamMood.forgotten),
      record(11, mood: DreamMood.good, score: 5),
    ], today: DateTime(2026, 11, 10));
    expect(result.statusCounts[DreamStatusCategory.good], 0);
    expect(result.statusCounts[DreamStatusCategory.unfilled], 0);
    expect(result.activity.elapsedDays, 2);
    expect(result.averageScore, 1);
    expect(result.scoreBuckets[2].average, isNull);
    expect(result.scoreBuckets[2].isFuture, isTrue);
  });
  test('均值按每日评分加权，null不当0，无评分桶留空', () {
    final result = stats(
      [
        record(1, score: 1),
        record(2, score: 1),
        record(3, score: 1),
        record(9, score: 5),
      ],
      period: StatisticsPeriod.month,
      today: DateTime(2026, 11, 30),
    );
    expect(result.averageScore, 2);
    expect(result.scoreSampleCount, 4);
    expect(result.scoreBuckets.first.average, 1);
    expect(result.scoreBuckets[1].average, 5);
    expect(result.scoreBuckets[2].average, isNull);
    expect(result.scoreBuckets.last.average, isNull);
  });
  test('评分和因素独立于状态与正文存在', () {
    final result = stats([
      record(9, score: 2),
      record(10, factors: {SleepFactor.health}),
    ]);
    expect(result.averageScore, 2);
    expect(result.goodShare, isNull);
    expect(result.moodInsight, MoodInsight.none);
    expect(result.topFactors, [SleepFactor.health]);
    expect(result.activity.recordedDays, 0);
  });
  for (final (year, month, length) in [
    (2026, 2, 28),
    (2028, 2, 29),
    (2026, 4, 30),
    (2026, 1, 31),
  ]) {
    test('$year/$month 评分按固定七天分组，最后一日恰好纳入一次', () {
      final result = SleepFeedbackStatistics(
        window: StatisticsWindow(StatisticsPeriod.month, DateTime(year, month)),
        records: [
          for (var day = 1; day <= length; day++)
            StatisticsRecord(
              date: DateTime(year, month, day),
              hasContent: false,
              feedback: const DailyFeedback(sleepScore: 4),
            ),
        ],
        today: DateTime(year, month + 1),
      );
      expect(
        result.scoreBuckets.map((b) => b.start.day),
        length == 28 ? [1, 8, 15, 22] : [1, 8, 15, 22, 29],
      );
      expect(result.scoreBuckets.last.end, DateTime(year, month + 1));
      expect(
        result.scoreBuckets.map((b) => b.sampleCount).reduce((a, b) => a + b),
        length,
      );
      expect(result.scoreBuckets.every((b) => b.average == 4), isTrue);
      expect(
        result.scoreBuckets.take(4).every((b) => b.sampleCount == 7),
        isTrue,
      );
    });
  }
  test('固定月组的7/8、14/15、28/29边界不串组，当前组排除未来评分', () {
    final records = [
      for (final day in [7, 8, 14, 15, 28, 29])
        record(day, score: day == 29 ? 5 : 1),
    ];
    final complete = stats(
      records,
      period: StatisticsPeriod.month,
      today: DateTime(2026, 11, 30),
    );
    expect(complete.scoreBuckets.map((b) => b.sampleCount), [1, 2, 1, 1, 1]);
    expect(complete.scoreBuckets.last.average, 5);
    final current = stats(
      records,
      period: StatisticsPeriod.month,
      today: DateTime(2026, 11, 14),
    );
    expect(current.scoreBuckets.map((b) => b.sampleCount), [1, 2, 0, 0, 0]);
    expect(current.scoreBuckets[2].isFuture, isTrue);
  });
  test('周状态保留日期位置，未填和未来状态不着色，没做梦仍为显式状态', () {
    final result = stats([
      record(9, mood: DreamMood.good),
      record(10, score: 4),
      record(11, mood: DreamMood.noDream),
      record(12, mood: DreamMood.nightmare),
    ], today: DateTime(2026, 11, 11));
    expect(result.weekDays.map((d) => d.date.day), [9, 10, 11, 12, 13, 14, 15]);
    expect(result.weekDays.map((d) => d.mood), [
      DreamMood.good,
      null,
      DreamMood.noDream,
      null,
      null,
      null,
      null,
    ]);
    expect(result.weekDays[1].isFuture, isFalse);
    expect(result.weekDays[3].isFuture, isTrue);
  });
  test('因素按日期集合计频，最多三项；并列按原选项顺序，不列零次项', () {
    final result = stats([
      record(
        9,
        factors: {
          SleepFactor.health,
          SleepFactor.stress,
          SleepFactor.emotion,
          SleepFactor.caffeine,
        },
      ),
      record(10, factors: {SleepFactor.health}),
      record(11, factors: {SleepFactor.health, SleepFactor.caffeine}),
    ]);
    expect(result.topFactors, [
      SleepFactor.health,
      SleepFactor.caffeine,
      SleepFactor.stress,
    ]);
    expect(result.factorFrequencies[SleepFactor.health], 3);
    expect(result.factorFrequencies[SleepFactor.screen], 0);
    expect(stats([]).topFactors, isEmpty);
    expect(
      stats([
        record(9, factors: {SleepFactor.unsure}),
      ]).topFactors,
      [SleepFactor.unsure],
    );
  });
  test('同日投影去重，更新反馈不会重复计数', () {
    final result = stats([
      record(9, mood: DreamMood.nightmare, score: 1),
      record(9, mood: DreamMood.good, score: 5),
    ]);
    expect(result.goodCount, 1);
    expect(result.nightmareCount, 0);
    expect(result.averageScore, 5);
  });
  for (final (good, bad, insight) in [
    (0, 0, MoodInsight.none),
    (1, 0, MoodInsight.allGood),
    (0, 1, MoodInsight.allNightmare),
    (1, 1, MoodInsight.similar),
    (2, 3, MoodInsight.similar),
    (3, 2, MoodInsight.similar),
    (4, 1, MoodInsight.mostlyGood),
    (1, 4, MoodInsight.mostlyNightmare),
  ]) {
    test('定性分析边界 $good/$bad → $insight', () {
      expect(
        stats([
          for (var i = 0; i < good + bad; i++)
            record(
              9 + i,
              mood: i < good ? DreamMood.good : DreamMood.nightmare,
            ),
        ]).moodInsight,
        insight,
      );
    });
  }
  test('跨年周、闰年全年按所属日期归类，未来周期没有评分或缺失夜晚', () {
    final result = SleepFeedbackStatistics(
      window: StatisticsWindow(StatisticsPeriod.year, DateTime(2028)),
      records: [
        StatisticsRecord(
          date: DateTime(2028, 2, 29),
          hasContent: false,
          feedback: const DailyFeedback(sleepScore: 4, mood: DreamMood.good),
        ),
      ],
      today: DateTime(2029),
    );
    expect(result.activity.elapsedDays, 366);
    expect(result.scoreBuckets[1].average, 4);
    expect(result.statusCounts[DreamStatusCategory.unfilled], 365);
    final future = SleepFeedbackStatistics(
      window: StatisticsWindow(StatisticsPeriod.year, DateTime(2029)),
      records: [],
      today: DateTime(2028),
    );
    expect(future.averageScore, isNull);
    expect(future.statusCounts.values.reduce((a, b) => a + b), 0);
    final week = SleepFeedbackStatistics(
      window: StatisticsWindow(StatisticsPeriod.week, DateTime(2027, 1, 1)),
      records: [
        StatisticsRecord(
          date: DateTime(2026, 12, 31),
          hasContent: false,
          feedback: const DailyFeedback(mood: DreamMood.noDream),
        ),
      ],
      today: DateTime(2027, 1, 3),
    );
    expect(week.statusCounts[DreamStatusCategory.noDream], 1);
  });
}
