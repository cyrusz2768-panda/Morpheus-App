import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

enum StatisticsPeriod { week, month, year }

/// 统计窗口是本地日历区间 [start, end)，不是 UTC 时间段。
/// 周从周一开始；月、年使用自然月/自然年。用日历构造函数进位，避免
/// “一个月等于30天”以及夏令时一天不总是24小时的问题。
class StatisticsWindow {
  StatisticsWindow(this.period, DateTime anchor)
    : start = switch (period) {
        StatisticsPeriod.week => DateTime(
          anchor.year,
          anchor.month,
          anchor.day - anchor.weekday + 1,
        ),
        StatisticsPeriod.month => DateTime(anchor.year, anchor.month),
        StatisticsPeriod.year => DateTime(anchor.year),
      };

  final StatisticsPeriod period;
  final DateTime start;

  DateTime get end => switch (period) {
    StatisticsPeriod.week => DateTime(start.year, start.month, start.day + 7),
    StatisticsPeriod.month => DateTime(start.year, start.month + 1),
    StatisticsPeriod.year => DateTime(start.year + 1),
  };

  StatisticsWindow move(int offset) =>
      StatisticsWindow(period, switch (period) {
        StatisticsPeriod.week => DateTime(
          start.year,
          start.month,
          start.day + 7 * offset,
        ),
        StatisticsPeriod.month => DateTime(start.year, start.month + offset),
        StatisticsPeriod.year => DateTime(start.year + offset),
      });

  /// 只借 UTC 计算两个日历日期之间的格数，不转换梦境日期所属的时区。
  static int daysBetween(DateTime start, DateTime end) => DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

  @override
  bool operator ==(Object other) =>
      other is StatisticsWindow &&
      period == other.period &&
      start == other.start;

  @override
  int get hashCode => Object.hash(period, start);
}

class StatisticsBucket {
  const StatisticsBucket({
    required this.start,
    required this.end,
    required this.recordedDays,
    required this.elapsedDays,
  });
  final DateTime start;
  final DateTime end;
  final int recordedDays;
  final int elapsedDays;
}

/// 不缓存另一份统计表。每次收到日期投影都重新计算，补记计入梦境所属
/// 周期，修改正文不会增加天数，删除后自然移除。这里只处理日期、不读取正文。
class DreamStatistics {
  DreamStatistics({
    required this.window,
    required Set<String> dateKeys,
    required DateTime today,
  }) {
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final cutoff = tomorrow.isBefore(window.end) ? tomorrow : window.end;
    elapsedDays = StatisticsWindow.daysBetween(
      window.start,
      cutoff,
    ).clamp(0, StatisticsWindow.daysBetween(window.start, window.end));
    final dates = dateKeys.map(DateTime.parse).map(DreamEntry.dateOnly).toSet();
    bool inside(DateTime date, DateTime start, DateTime end) =>
        !date.isBefore(start) && date.isBefore(end);
    final current = dates.where((date) => inside(date, window.start, cutoff));
    recordedDays = current.length;
    weekendDays = current
        .where((date) => date.weekday >= DateTime.saturday)
        .length;

    final previous = window.move(-1);
    // 当前周期未结束时只比较上期相同经过天数；上期较短时取其完整周期。
    // 已结束的历史周期则比较两个完整周期。只显示天数差，不夸大成增长率。
    final comparisonEnd = StatisticsWindow(window.period, today) == window
        ? DateTime(
            previous.start.year,
            previous.start.month,
            previous.start.day + elapsedDays,
          )
        : previous.end;
    final previousCutoff = comparisonEnd.isBefore(previous.end)
        ? comparisonEnd
        : previous.end;
    previousRecordedDays = dates
        .where((date) => inside(date, previous.start, previousCutoff))
        .length;

    final result = <StatisticsBucket>[];
    var cursor = window.start;
    while (cursor.isBefore(window.end)) {
      // 周按天，月按周一分组（首尾可不足一周），年按月，避免31根细柱
      // 在手机上拥挤。每个分组均被裁切在本周期内部，不混入邻月/邻年。
      var next = switch (window.period) {
        StatisticsPeriod.week => DateTime(
          cursor.year,
          cursor.month,
          cursor.day + 1,
        ),
        StatisticsPeriod.month => DateTime(
          cursor.year,
          cursor.month,
          cursor.day + 8 - cursor.weekday,
        ),
        StatisticsPeriod.year => DateTime(cursor.year, cursor.month + 1),
      };
      if (next.isAfter(window.end)) next = window.end;
      final eligibleEnd = cutoff.isBefore(next) ? cutoff : next;
      result.add(
        StatisticsBucket(
          start: cursor,
          end: next,
          recordedDays: current
              .where((date) => inside(date, cursor, next))
              .length,
          elapsedDays: StatisticsWindow.daysBetween(
            cursor,
            eligibleEnd,
          ).clamp(0, 366),
        ),
      );
      cursor = next;
    }
    buckets = List.unmodifiable(result);
  }

  final StatisticsWindow window;
  late final int elapsedDays;
  late final int recordedDays;
  late final int weekendDays;
  late final int previousRecordedDays;
  late final List<StatisticsBucket> buckets;
  int get weekdayDays => recordedDays - weekendDays;
  double get coverage => elapsedDays == 0 ? 0 : recordedDays / elapsedDays;
  double get weekendShare => recordedDays == 0 ? 0 : weekendDays / recordedDays;
}
