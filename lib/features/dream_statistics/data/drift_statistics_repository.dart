import 'dart:convert';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';
import 'package:drift/drift.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_statistics/data/statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

class DriftStatisticsRepository implements IStatisticsRepository {
  DriftStatisticsRepository(this._database);
  final AppDatabase _database;

  @override
  Stream<Set<String>> watchRecordedDates(StatisticsWindow window) =>
      watchRecords(window).map(
        (records) => Set.unmodifiable(
          records
              .where((r) => r.hasContent)
              .map((r) => DreamEntry.dateKey(r.date)),
        ),
      );

  @override
  Stream<List<StatisticsRecord>> watchRecords(StatisticsWindow window) {
    final table = _database.dreamRecords;
    // SQLite 先按主键范围缩小查询（最多两年），不加载整个历史或时间戳。一次监听投影正文存在性与独立反馈。
    // 正文只在仓库内部用于兼容旧空白行；trim 支持换行与全角空白。
    final query = _database.selectOnly(table)
      ..addColumns([
        table.dreamDate,
        table.content,
        table.dreamMood,
        table.sleepScore,
        table.sleepFactors,
      ])
      ..where(
        table.dreamDate.isBiggerOrEqualValue(
              DreamEntry.dateKey(window.move(-1).start),
            ) &
            table.dreamDate.isSmallerThanValue(DreamEntry.dateKey(window.end)),
      );
    return query.watch().map(
      (rows) => List.unmodifiable(
        rows.map((row) {
          // JSON 损坏必须向上传递为读取失败，不能偷偷显示成“没有反馈”。
          final names =
              jsonDecode(row.read(table.sleepFactors) ?? '[]') as List;
          return StatisticsRecord(
            date: DateTime.parse(row.read(table.dreamDate)!),
            hasContent: row.read(table.content)!.trim().isNotEmpty,
            feedback: DailyFeedback(
              mood: DreamMood.values
                  .where((m) => m.name == row.read(table.dreamMood))
                  .firstOrNull,
              sleepScore: row.read(table.sleepScore),
              factors: Set.unmodifiable(
                SleepFactor.values.where((f) => names.contains(f.name)),
              ),
            ),
          );
        }),
      ),
    );
  }
}
