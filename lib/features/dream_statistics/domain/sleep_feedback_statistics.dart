import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

/// 统计专用投影，不把梦境正文传入统计页面，也不保存第二份统计表。
/// 一次数据库快照同时携带正文存在性与独立反馈，避免两条流短暂不同步。
class StatisticsRecord {
  const StatisticsRecord({
    required this.date,
    required this.hasContent,
    this.feedback = const DailyFeedback(),
  });
  final DateTime date;

  /// 正文、图片或链接任一存在即有梦境内容；同日多图仍只贡献一个日期。
  final bool hasContent;
  final DailyFeedback feedback;
}

/// 未填状态包含没有记录、跳过状态和旧版仅有正文；不能推断成“没做梦”。
enum DreamStatusCategory { good, nightmare, forgotten, noDream, unfilled }

enum MoodInsight {
  none,
  allGood,
  allNightmare,
  similar,
  mostlyGood,
  mostlyNightmare,
}

class SleepScoreBucket {
  const SleepScoreBucket({
    required this.start,
    required this.end,
    required this.sampleCount,
    required this.average,
    required this.isFuture,
  });
  final DateTime start;
  final DateTime end;
  final int sampleCount;
  final double? average;
  final bool isFuture;
}

/// 周网格需要逐日位置，不能从比例汇总反推哪一天填了哪种状态。
/// null 同时表示未填状态或未来日期，isFuture 只用于区分读屏提示。
class WeeklyDreamStatus {
  const WeeklyDreamStatus({
    required this.date,
    required this.mood,
    required this.isFuture,
  });
  final DateTime date;
  final DreamMood? mood;
  final bool isFuture;
}

/// 所有反馈按醒来当天的日期聚合，只取本期截至今天的数据。
/// 状态、评分、因素各用自己的有效样本，互不推算；活动日期包含正文、图片或链接。
class SleepFeedbackStatistics {
  SleepFeedbackStatistics({
    required StatisticsWindow window,
    required Iterable<StatisticsRecord> records,
    required DateTime today,
  }) {
    // 日期唯一性在数据库由主键保证，领域层也按日期去重，确保一天最多一次。
    final byDate = {
      for (final record in records) DreamEntry.dateKey(record.date): record,
    };
    activity = DreamStatistics(
      window: window,
      dateKeys: byDate.values
          .where((r) => r.hasContent)
          .map((r) => DreamEntry.dateKey(r.date))
          .toSet(),
      today: today,
    );
    final cutoff = DateTime(
      window.start.year,
      window.start.month,
      window.start.day + activity.elapsedDays,
    );
    bool inside(DateTime date, DateTime start, DateTime end) {
      final day = DreamEntry.dateOnly(date);
      return !day.isBefore(start) && day.isBefore(end);
    }

    final current = byDate.values
        .where((r) => inside(r.date, window.start, cutoff))
        .toList();
    final counts = {
      for (final category in DreamStatusCategory.values) category: 0,
    };
    for (final record in current) {
      final mood = record.feedback.mood;
      if (mood != null) {
        final category = DreamStatusCategory.values.byName(mood.name);
        counts[category] = counts[category]! + 1;
      }
    }
    counts[DreamStatusCategory.unfilled] =
        activity.elapsedDays - counts.values.reduce((a, b) => a + b);
    statusCounts = Map.unmodifiable(counts);
    final days = <WeeklyDreamStatus>[];
    if (window.period == StatisticsPeriod.week) {
      for (var offset = 0; offset < 7; offset++) {
        final date = DateTime(
          window.start.year,
          window.start.month,
          window.start.day + offset,
        );
        final isFuture = !date.isBefore(cutoff);
        days.add(
          WeeklyDreamStatus(
            date: date,
            mood: isFuture
                ? null
                : byDate[DreamEntry.dateKey(date)]?.feedback.mood,
            isFuture: isFuture,
          ),
        );
      }
    }
    weekDays = List.unmodifiable(days);

    // null 或越界值不进入平均分；没有样本时仍为 null，不把未知值补成0。
    List<int> scores(Iterable<StatisticsRecord> source) => source
        .map((r) => r.feedback.sleepScore)
        .whereType<int>()
        .where((s) => s >= 1 && s <= 5)
        .toList();
    double? mean(List<int> values) =>
        values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
    final values = scores(current);
    scoreSampleCount = values.length;
    averageScore = mean(values);
    // 评分月图从1日开始每7天一组，而不是按星期一切分。这样月份起始
    // 星期不同也不会出现“1日、2–8日”等不规则区间；月尾不足7天单独收尾。
    final buckets = <SleepScoreBucket>[];
    var cursor = window.start;
    while (cursor.isBefore(window.end)) {
      var end = switch (window.period) {
        StatisticsPeriod.week => DateTime(
          cursor.year,
          cursor.month,
          cursor.day + 1,
        ),
        StatisticsPeriod.month => DateTime(
          cursor.year,
          cursor.month,
          cursor.day + 7,
        ),
        StatisticsPeriod.year => DateTime(cursor.year, cursor.month + 1),
      };
      if (end.isAfter(window.end)) end = window.end;
      final samples = scores(current.where((r) => inside(r.date, cursor, end)));
      buckets.add(
        SleepScoreBucket(
          start: cursor,
          end: end,
          sampleCount: samples.length,
          isFuture: !cursor.isBefore(cutoff),
          average: mean(samples),
        ),
      );
      cursor = end;
    }
    scoreBuckets = List.unmodifiable(buckets);

    // 因素是每日多选集合，每项每天最多+1。只展示正频次的前三项；
    // 第三名并列时按原选项顺序稳定取舍，避免同数据刷新时随机换位。
    final frequency = {
      for (final factor in SleepFactor.values)
        factor: current
            .where((r) => r.feedback.factors.contains(factor))
            .length,
    };
    factorFrequencies = Map.unmodifiable(frequency);
    final ranked = SleepFactor.values.where((f) => frequency[f]! > 0).toList()
      ..sort((a, b) {
        final difference = frequency[b]!.compareTo(frequency[a]!);
        return difference != 0 ? difference : a.index.compareTo(b.index);
      });
    topFactors = List.unmodifiable(ranked.take(3));
  }

  late final DreamStatistics activity;
  late final Map<DreamStatusCategory, int> statusCounts;
  late final List<WeeklyDreamStatus> weekDays;
  late final int scoreSampleCount;
  late final double? averageScore;
  late final List<SleepScoreBucket> scoreBuckets;
  late final Map<SleepFactor, int> factorFrequencies;
  late final List<SleepFactor> topFactors;

  int get goodCount => statusCounts[DreamStatusCategory.good]!;
  int get nightmareCount => statusCounts[DreamStatusCategory.nightmare]!;
  int get classifiedDreamCount => goodCount + nightmareCount;
  double? get goodShare =>
      classifiedDreamCount == 0 ? null : goodCount / classifiedDreamCount;
  MoodInsight get moodInsight {
    final share = goodShare;
    if (share == null) return MoodInsight.none;
    if (nightmareCount == 0) return MoodInsight.allGood;
    if (goodCount == 0) return MoodInsight.allNightmare;
    if (share >= .4 && share <= .6) return MoodInsight.similar;
    return share > .6 ? MoodInsight.mostlyGood : MoodInsight.mostlyNightmare;
  }
}
