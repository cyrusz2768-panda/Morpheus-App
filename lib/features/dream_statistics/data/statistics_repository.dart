import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

/// 统计只需要有效记录的日期，不向页面暴露正文或数据库连接。
abstract interface class IStatisticsRepository {
  /// 单一快照包含日期、正文存在性与主观反馈；不向页面暴露正文。
  Stream<List<StatisticsRecord>> watchRecords(StatisticsWindow window);

  /// 返回本期及上期的日期快照，写入、修改和删除提交后实时更新。
  /// 读取失败必须传播异常，不能把故障当成零条记录。
  Stream<Set<String>> watchRecordedDates(StatisticsWindow window);
}
