import 'package:drift/drift.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_search/data/dream_search_repository.dart';

/// 在原有 SQLite 表上查询，共用应用级连接，不改表、不迁移或删除已有数据。
class DriftDreamSearchRepository implements IDreamSearchRepository {
  DriftDreamSearchRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<DreamEntry>> search(String keyword) async {
    final term = keyword.trim();
    if (term.isEmpty) return const [];

    // LIKE 默认把 % 和 _ 当作通配符。先转义转义符本身，再转义这两个字符，
    // 用户才能搜索“100%”或“a_b”的原文。Drift 用绑定参数传递整个模式，
    // 单引号等输入不会变成 SQL。SQLite LIKE 对 ASCII 英文字母忽略大小写。
    final escaped = term
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final query = _database.select(_database.dreamRecords)
      ..where((table) => table.content.like('%$escaped%', escapeChar: '\\'))
      ..orderBy([(table) => OrderingTerm.desc(table.dreamDate)]);
    final rows = await query.get();

    // SQL 只返回匹配记录，不把全部历史搬进页面；此处兼容旧版的纯空白行。
    // 正文保持原样，列表摘要的空白压缩仅发生在显示层。
    return List<DreamEntry>.unmodifiable(
      rows.where((row) => row.content.trim().isNotEmpty).map((row) {
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
      }),
    );
  }
}
