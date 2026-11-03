import 'package:drift/drift.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/data/dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// 将领域层的“读取 / 保存 / 删除梦境”转换成真正的 SQLite 操作。
///
/// UI 仍然只依赖 DreamRepository 接口。以后替换存储或添加导出功能时，
/// 不必把 SQL 塞进页面。数据库由外部 Provider 持有，Repository 不自行关闭它。
class DriftDreamRepository implements DreamRepository {
  DriftDreamRepository(this._database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _database;

  // 注入时钟可以让测试准确验证创建/更新时间，而不依赖电脑的当前时间。
  final DateTime Function() _now;

  @override
  Future<DreamEntry?> getByDate(DateTime date) async {
    final key = DreamEntry.dateKey(date);
    final query = _database.select(_database.dreamRecords)
      ..where((table) => table.dreamDate.equals(key));
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
  }) async {
    // trim 只用来判断“有没有正文”，不把 trim 后的文字保存回去。
    // 清空文本的情形由 Controller 调用 deleteByDate；直接误用 save 时应报错，
    // 而不是创建一条无意义的空梦境记录。
    if (content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content', '正文不能为空白，请使用删除操作');
    }

    final key = DreamEntry.dateKey(date);
    final nowMillis = _now().toUtc().millisecondsSinceEpoch;

    // transaction 把写入与回读作为一个整体，失败时回滚，不把失败伪装成“已保存”。
    // DoUpdate 生成 INSERT ... ON CONFLICT DO UPDATE：同一天更新正文和
    // updatedAtMillis，但绝不覆盖第一次写入的 createdAtMillis。
    return _database.transaction(() async {
      await _database
          .into(_database.dreamRecords)
          .insert(
            DreamRecordsCompanion.insert(
              dreamDate: key,
              content: content,
              createdAtMillis: nowMillis,
              updatedAtMillis: nowMillis,
            ),
            onConflict: DoUpdate(
              (_) => DreamRecordsCompanion(
                content: Value(content),
                updatedAtMillis: Value(nowMillis),
              ),
              target: [_database.dreamRecords.dreamDate],
            ),
          );

      // 必须等 SQL 成功完成后才返回，Controller 随后才能显示“已保存”。
      final row = await (_database.select(
        _database.dreamRecords,
      )..where((table) => table.dreamDate.equals(key))).getSingle();
      return _toDomain(row);
    });
  }

  @override
  Future<void> deleteByDate(DateTime date) async {
    final key = DreamEntry.dateKey(date);
    await (_database.delete(
      _database.dreamRecords,
    )..where((table) => table.dreamDate.equals(key))).go();
  }

  /// 数据库存储格式只在本层转换，领域对象保持原有 API。
  DreamEntry _toDomain(DreamRecordRow row) {
    return DreamEntry(
      id: row.dreamDate,
      dreamDate: DateTime.parse(row.dreamDate),
      content: row.content,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.createdAtMillis,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.updatedAtMillis,
        isUtc: true,
      ),
    );
  }
}
