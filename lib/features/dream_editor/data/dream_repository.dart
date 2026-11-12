import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// 编辑器与历史页面共用的存储契约。
///
/// 正式应用由 Drift / SQLite 实现，测试可以注入内存实现。页面只需要知道
/// “读某天、读历史、保存、删除”，不需要直接操作数据库或了解 SQL。
abstract interface class DreamRepository {
  /// Reads the entry associated with [date], or returns null when none exists.
  Future<DreamEntry?> getByDate(DateTime date);

  /// 返回有正文或主观反馈的全部记录，按梦境日期从近到远排列，每个日期最多一条。
  ///
  /// 排序依据是 dreamDate，而不是 updatedAt：今天补记上个月的梦，仍应出现在
  /// 上个月的位置。没有记录时返回空列表；读取失败仍向上传递异常，让页面显示
  /// “读取失败”和重试入口，不能把失败伪装成“尚无历史梦境”。
  Future<List<DreamEntry>> getAll();

  /// Creates or updates the entry for [date].
  ///
  /// M1 permits one entry per local calendar day, so this operation behaves as
  /// an "upsert": update if present, insert otherwise.
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
    DailyFeedback? feedback,
  });

  /// Deletes the entry for [date]. Deleting a missing entry is harmless.
  Future<void> deleteByDate(DateTime date);
}
