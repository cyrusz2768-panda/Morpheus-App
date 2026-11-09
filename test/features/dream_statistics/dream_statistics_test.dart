import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

void main() {
  test('周一开周，跨年周包含两年日期', () {
    final window = StatisticsWindow(
      StatisticsPeriod.week,
      DateTime(2027, 1, 3),
    );
    expect(window.start, DateTime(2026, 12, 28));
    expect(window.end, DateTime(2027, 1, 4));
    expect(window.move(1).start, window.end);
    expect(
      window,
      StatisticsWindow(StatisticsPeriod.week, DateTime(2026, 12, 31)),
    );
    final stats = DreamStatistics(
      window: window,
      dateKeys: {'2026-12-28', '2027-01-02', '2027-01-03', '2027-01-04'},
      today: DateTime(2027, 1, 3),
    );
    expect(stats.recordedDays, 3);
    expect(stats.weekendDays, 2);
    expect(stats.weekdayDays, 1);
    expect(stats.buckets.map((bucket) => bucket.recordedDays), [
      1,
      0,
      0,
      0,
      0,
      1,
      1,
    ]);
  });

  test('闰月分组只包含本月，每一天恰好分配一次', () {
    final window = StatisticsWindow(
      StatisticsPeriod.month,
      DateTime(2028, 2, 29),
    );
    final keys = {
      for (var day = 1; day <= 29; day++)
        '2028-02-${day.toString().padLeft(2, '0')}',
    };
    final stats = DreamStatistics(
      window: window,
      dateKeys: keys,
      today: DateTime(2028, 3),
    );
    expect(stats.elapsedDays, 29);
    expect(stats.recordedDays, 29);
    expect(stats.coverage, 1);
    expect(
      stats.buckets
          .map((bucket) => bucket.recordedDays)
          .reduce((a, b) => a + b),
      29,
    );
    expect(stats.buckets.first.start, window.start);
    expect(stats.buckets.last.end, window.end);
    expect(window.move(-1).start, DateTime(2028, 1));
    expect(window.move(1).start, DateTime(2028, 3));
  });

  test('年视图包含闰日、十二月，不混入邻年', () {
    final stats = DreamStatistics(
      window: StatisticsWindow(StatisticsPeriod.year, DateTime(2028)),
      dateKeys: {'2027-12-31', '2028-02-29', '2028-12-31', '2029-01-01'},
      today: DateTime(2029),
    );
    expect(stats.elapsedDays, 366);
    expect(stats.recordedDays, 2);
    expect(stats.buckets.length, 12);
    expect(stats.buckets[1].recordedDays, 1);
    expect(stats.buckets.last.recordedDays, 1);
    expect(stats.previousRecordedDays, 1);
  });

  test('当前周期不计未来，分母截至今天，上期取相同经过天数', () {
    final stats = DreamStatistics(
      window: StatisticsWindow(StatisticsPeriod.month, DateTime(2026, 11)),
      dateKeys: {
        '2026-10-01',
        '2026-10-11',
        '2026-11-01',
        '2026-11-10',
        '2026-11-11',
      },
      today: DateTime(2026, 11, 10, 23, 59),
    );
    expect(stats.elapsedDays, 10);
    expect(stats.recordedDays, 2);
    expect(stats.coverage, .2);
    expect(stats.previousRecordedDays, 1);
    expect(stats.buckets.last.elapsedDays, 0);
  });

  test('上月较短时同期不越界到本月，完整历史周期比较完整上期', () {
    final keys = {'2028-02-29', '2028-03-01', '2028-03-30'};
    final window = StatisticsWindow(StatisticsPeriod.month, DateTime(2028, 3));
    final current = DreamStatistics(
      window: window,
      dateKeys: keys,
      today: DateTime(2028, 3, 30),
    );
    expect(current.previousRecordedDays, 1);
    final historical = DreamStatistics(
      window: window,
      dateKeys: keys,
      today: DateTime(2028, 4),
    );
    expect(historical.elapsedDays, 31);
    expect(historical.previousRecordedDays, 1);
  });

  test('当前短月最后一天仍按同期比较，不额外计入上月31日', () {
    final stats = DreamStatistics(
      window: StatisticsWindow(StatisticsPeriod.month, DateTime(2026, 4)),
      dateKeys: {'2026-03-30', '2026-03-31'},
      today: DateTime(2026, 4, 30),
    );
    expect(stats.previousRecordedDays, 1);
  });

  test('零记录和未来窗口没有除零，UTC输入按日历字段处理', () {
    final stats = DreamStatistics(
      window: StatisticsWindow(
        StatisticsPeriod.month,
        DateTime.utc(2026, 12, 31, 23),
      ),
      dateKeys: {},
      today: DateTime(2026, 11, 10),
    );
    expect(stats.window.start, DateTime(2026, 12));
    expect(stats.elapsedDays, 0);
    expect(stats.recordedDays, 0);
    expect(stats.coverage, 0);
    expect(stats.weekendShare, 0);
    expect(
      StatisticsWindow.daysBetween(DateTime(2026, 3, 1), DateTime(2026, 4, 1)),
      31,
    );
  });
}
