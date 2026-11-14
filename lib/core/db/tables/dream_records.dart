import 'package:drift/drift.dart';

/// SQLite 中保存梦境的表。这里的 Dart 声明是“建表蓝图”，不是已经保存的数据。
///
/// Drift 代码生成器会读取这些列，生成 SQL、查询方法和 `DreamRecordRow` 行对象。
/// 领域层的 DreamEntry 与数据库行分开，页面不需要了解 SQLite 的列名和存储格式。
@DataClassName('DreamRecordRow')
class DreamRecords extends Table {
  /// M1 每个日期只有一条记录，因此日期字符串本身就可以作为唯一主键。
  ///
  /// 保存 `2026-11-03`，而不是某个 UTC 午夜的时间戳：梦境属于用户选择的
  /// 日历日期，不应因为设备时区改变而自动变成前一天或后一天。
  TextColumn get dreamDate => text()();

  /// 正文按原样保存，包括换行、中文、emoji 和用户有意输入的首尾空格。
  /// 纯空白内容的业务处理在 Repository / Controller 中完成。
  TextColumn get content => text()();

  /// 记录创建、更新时间使用 UTC Unix 毫秒数，表示全球统一的时间点。
  ///
  /// 显式使用 integer，避免默认日期存储精度产生歧义；读取时再转换成
  /// DateTime.fromMillisecondsSinceEpoch(..., isUtc: true)。
  IntColumn get createdAtMillis => integer()();
  IntColumn get updatedAtMillis => integer()();

  /// v2 新列全部允许未填写。旧记录迁移后不会被推断为某种梦或 0 分。
  TextColumn get dreamMood => text().nullable()();
  IntColumn get sleepScore => integer().nullable().customConstraint(
    'CHECK (sleep_score BETWEEN 1 AND 5)',
  )();
  TextColumn get sleepFactors => text().nullable()();
  BoolColumn get flowCompleted =>
      boolean().withDefault(const Constant(false))();

  /// v3 附件元数据；原始图片存于私有目录，旧记录默认无附件。
  TextColumn get images => text().withDefault(const Constant('[]'))();

  /// v4 网页/音乐链接元数据；旧文字、反馈及图片引用保持原样。
  TextColumn get links => text().withDefault(const Constant('[]'))();

  /// 主键由数据库强制唯一，而不只靠 Dart 代码“先检查有没有”。
  /// 即使同一天发生重复写入，SQLite 也不会产生两条相同日期的记录。
  @override
  Set<Column<Object>> get primaryKey => {dreamDate};
}
