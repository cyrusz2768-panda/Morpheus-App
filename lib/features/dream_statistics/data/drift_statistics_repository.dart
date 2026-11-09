import 'package:drift/drift.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_statistics/data/statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

class DriftStatisticsRepository implements IStatisticsRepository {
  DriftStatisticsRepository(this._database);
  final AppDatabase _database;

  @override
  Stream<Set<String>> watchRecordedDates(StatisticsWindow window) {
    final table = _database.dreamRecords;
    // SQLite 先按主键范围缩小查询（最多两年），不加载整个历史或时间戳。
    // 正文只在仓库内部用于兼容旧空白行；trim 支持换行与全角空白。
    final query = _database.selectOnly(table)
      ..addColumns([table.dreamDate, table.content])
      ..where(
        table.dreamDate.isBiggerOrEqualValue(
              DreamEntry.dateKey(window.move(-1).start),
            ) &
            table.dreamDate.isSmallerThanValue(DreamEntry.dateKey(window.end)),
      );
    return query.watch().map(
      (rows) => Set<String>.unmodifiable(
        rows
            .where((row) => row.read(table.content)!.trim().isNotEmpty)
            .map((row) => row.read(table.dreamDate)!),
      ),
    );
  }
}
