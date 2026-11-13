import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'dart:convert';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
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
  Future<List<DreamEntry>> getAll() async {
    // 日期统一保存为 yyyy-mm-dd，所以 SQL 文本降序就是日历日期降序。
    // 排序放在查询层完成，页面无需重复排序，也不会把“最近修改的旧梦境”
    // 错当成“最近日期的梦境”。v2 仍沿用同一日期主键。
    final query = _database.select(_database.dreamRecords)
      ..orderBy([(table) => OrderingTerm.desc(table.dreamDate)]);
    final rows = await query.get();

    // 仅有完成标记的日期不作为历史反馈，旧版本空白行同样过滤。
    // Dart trim 能处理换行、制表符等空白，比 SQLite 默认 TRIM 的空格规则完整。
    // 返回只读快照；编辑和删除必须通过对应 Repository 方法真正写入数据库。
    return List<DreamEntry>.unmodifiable(
      rows.map(_toDomain).where((entry) => entry.hasData),
    );
  }

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
    DailyFeedback? feedback,
    List<DreamImage>? images,
  }) async {
    // 省略 feedback 的旧调用只修改正文，保留当天已有反馈。
    // Controller 提交完整快照，确保清空正文不会连带删除评分和状态。
    final key = DreamEntry.dateKey(date);
    final nowMillis = _now().toUtc().millisecondsSinceEpoch;

    // transaction 把写入与回读作为一个整体，失败时回滚，不把失败伪装成“已保存”。
    // DoUpdate 生成 INSERT ... ON CONFLICT DO UPDATE：同一天更新正文和
    // updatedAtMillis，但绝不覆盖第一次写入的 createdAtMillis。
    return _database.transaction(() async {
      final existing = await getByDate(date);
      final savedImages = List<DreamImage>.unmodifiable(
        images ?? existing?.images ?? const [],
      );
      final savedFeedback =
          feedback ?? existing?.feedback ?? const DailyFeedback();
      if (content.trim().isEmpty &&
          savedImages.isEmpty &&
          !savedFeedback.hasData &&
          !savedFeedback.completed) {
        throw ArgumentError('记录没有正文或反馈，请使用删除操作');
      }

      await _database
          .into(_database.dreamRecords)
          .insert(
            DreamRecordsCompanion.insert(
              dreamDate: key,
              content: content,
              images: Value(DreamImage.encode(savedImages)),
              dreamMood: Value(savedFeedback.mood?.name),
              sleepScore: Value(savedFeedback.sleepScore),
              sleepFactors: Value(
                jsonEncode(savedFeedback.factors.map((e) => e.name).toList()),
              ),
              flowCompleted: Value(savedFeedback.completed),
              createdAtMillis: nowMillis,
              updatedAtMillis: nowMillis,
            ),
            onConflict: DoUpdate(
              (_) => DreamRecordsCompanion(
                content: Value(content),
                images: Value(DreamImage.encode(savedImages)),
                dreamMood: Value(savedFeedback.mood?.name),
                sleepScore: Value(savedFeedback.sleepScore),
                sleepFactors: Value(
                  jsonEncode(savedFeedback.factors.map((e) => e.name).toList()),
                ),
                flowCompleted: Value(savedFeedback.completed),
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
      images: DreamImage.decode(row.images),
      feedback: DailyFeedback(
        mood: DreamMood.values
            .where((e) => e.name == row.dreamMood)
            .firstOrNull,
        sleepScore: row.sleepScore,
        factors: Set.unmodifiable(
          SleepFactor.values.where(
            (e) =>
                (jsonDecode(row.sleepFactors ?? '[]') as List).contains(e.name),
          ),
        ),
        completed: row.flowCompleted,
      ),
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
