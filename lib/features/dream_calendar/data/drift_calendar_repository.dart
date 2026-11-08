import 'package:drift/drift.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_calendar/data/calendar_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// 从现有 dream_records 表派生月历标记，不创建另一张需要同步的“标记表”。
///
/// Repository 与编辑器共用数据库连接，Drift 会在写入提交后重新执行监听查询。
/// 因而保存 / 清空删除与月历圆点来自同一份真实数据，不依赖手动刷新缓存。
/// 连接生命周期由 appDatabaseProvider 管理，本类不负责打开或关闭数据库。
class DriftCalendarRepository implements ICalendarRepository {
  DriftCalendarRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<Set<String>> watchRecordedDatesInMonth(DateTime month) {
    // 用年月构造边界，DateTime 会自动处理十二月到下一年一月的进位。
    // 不用“加 30 天”推算下个月，也不做 UTC 转换，避免短月、闰日和时区偏移。
    final start = DreamEntry.dateKey(DateTime(month.year, month.month));
    final end = DreamEntry.dateKey(DateTime(month.year, month.month + 1));
    final table = _database.dreamRecords;

    // yyyy-mm-dd 文本键可以直接按字典顺序比较；[月初, 下月月初) 同时包含
    // 当月第一天与最后一天，并排除邻月。范围条件在 SQLite 中执行，而不是
    // 先 getAll() 把多年历史传回 Dart 再筛选。日期主键保证正常数据每月最多 31 行。
    // selectOnly 只取日期与正文，不读取本查询用不到的创建 / 更新时间。
    final query = _database.selectOnly(table)
      ..addColumns([table.dreamDate, table.content])
      ..where(
        table.dreamDate.isBiggerOrEqualValue(start) &
            table.dreamDate.isSmallerThanValue(end),
      );

    return query.watch().map((rows) {
      // 正常保存会拒绝空白正文；仍兼容旧版 / 导入留下的空行。使用 Dart trim
      // 处理换行、制表符及全角空格，比 SQLite 默认 TRIM 只处理空格更完整。
      // 返回只读快照，防止页面修改集合后污染已经发布的状态。
      return Set<String>.unmodifiable(
        rows
            .where((row) => row.read(table.content)!.trim().isNotEmpty)
            .map((row) => row.read(table.dreamDate)!),
      );
    });
  }
}
