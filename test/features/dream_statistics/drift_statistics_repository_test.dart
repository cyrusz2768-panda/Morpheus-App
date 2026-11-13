import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';
import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';
import 'package:morpheus/features/dream_statistics/data/drift_statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

void main() {
  test('真实 SQLite 监听补记、修改、删除；统计归属日期而非写入时间', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final editor = DriftDreamRepository(database);
    final window = StatisticsWindow(StatisticsPeriod.month, DateTime(2024, 2));
    final stream = StreamIterator(
      DriftStatisticsRepository(database).watchRecordedDates(window),
    );
    addTearDown(stream.cancel);
    Future<void> expectNext(Set<String> expected) async {
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      expect(stream.current, expected);
    }

    await expectNext({});
    await editor.save(date: DateTime(2024, 2, 29), content: '今天补记过去的闰日');
    await expectNext({'2024-02-29'});
    await editor.save(date: DateTime(2024, 2, 29), content: '修改后仍计一天');
    await expectNext({'2024-02-29'});
    await editor.save(date: DateTime(2024, 1, 31), content: '上期比较记录');
    await expectNext({'2024-01-31', '2024-02-29'});
    final stats = DreamStatistics(
      window: window,
      dateKeys: stream.current,
      today: DateTime(2026),
    );
    expect(stats.recordedDays, 1);
    expect(stats.previousRecordedDays, 1);
    expect(() => stream.current.clear(), throwsUnsupportedError);
    await editor.deleteByDate(DateTime(2024, 2, 29));
    await expectNext({'2024-01-31'});
  });

  test('范围含本期和上期首尾，过滤旧 Unicode 空白，不改写原数据', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final editor = DriftDreamRepository(database);
    for (final date in [
      DateTime(2023, 12, 31),
      DateTime(2024, 1, 1),
      DateTime(2024, 2, 29),
      DateTime(2024, 3, 1),
    ]) {
      await editor.save(date: date, content: '边界人工数据');
    }
    await database
        .into(database.dreamRecords)
        .insert(
          DreamRecordsCompanion.insert(
            dreamDate: '2024-02-02',
            content: '\n\t\u3000\u00a0',
            createdAtMillis: 0,
            updatedAtMillis: 0,
          ),
        );
    final dates = await DriftStatisticsRepository(database)
        .watchRecordedDates(
          StatisticsWindow(
            StatisticsPeriod.month,
            DateTime.utc(2024, 2, 29, 23),
          ),
        )
        .first;
    expect(dates, {'2024-01-01', '2024-02-29'});
    expect(await database.select(database.dreamRecords).get(), hasLength(5));
  });

  test('关闭重开真实临时文件仍从持久化记录恢复统计', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus_statistics_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/test.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    final editor = DriftDreamRepository(first);
    await editor.save(date: DateTime(2025, 12, 31), content: '测试梦境');
    await editor.save(date: DateTime(2026, 1, 1), content: '随后删除');
    await editor.deleteByDate(DateTime(2026, 1, 1));
    await first.close();
    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final dates = await DriftStatisticsRepository(second)
        .watchRecordedDates(
          StatisticsWindow(StatisticsPeriod.year, DateTime(2026)),
        )
        .first;
    expect(dates, {'2025-12-31'});
  });
  test('反馈投影实时更新，独立评分/因素无需正文，清除后不留旧值', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final editor = DriftDreamRepository(database);
    final window = StatisticsWindow(
      StatisticsPeriod.week,
      DateTime(2026, 11, 12),
    );
    final iterator = StreamIterator(
      DriftStatisticsRepository(database).watchRecords(window),
    );
    addTearDown(iterator.cancel);
    Future<List<StatisticsRecord>> next() async {
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      return iterator.current;
    }

    expect(await next(), isEmpty);
    final date = DateTime(2026, 11, 12);
    await editor.save(
      date: date,
      content: '',
      feedback: const DailyFeedback(
        sleepScore: 4,
        factors: {SleepFactor.stress},
      ),
    );
    final first = (await next()).single;
    expect(first.hasContent, isFalse);
    expect(first.feedback.mood, isNull);
    expect(first.feedback.sleepScore, 4);
    expect(first.feedback.factors, {SleepFactor.stress});
    await editor.save(
      date: date,
      content: '',
      feedback: const DailyFeedback(mood: DreamMood.noDream),
    );
    final updated = (await next()).single;
    expect(updated.feedback.sleepScore, isNull);
    expect(updated.feedback.factors, isEmpty);
    expect(updated.feedback.mood, DreamMood.noDream);
    await editor.deleteByDate(date);
    expect(await next(), isEmpty);
  });

  test('反馈关闭重开真实文件恢复，范围边界准确且不携带原文', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus_sleep_statistics_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/feedback.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    final editor = DriftDreamRepository(first);
    for (final date in [
      DateTime(2025, 12, 31),
      DateTime(2026, 1, 1),
      DateTime(2026, 11, 12),
      DateTime(2027, 1, 1),
    ]) {
      await editor.save(
        date: date,
        content: '',
        feedback: const DailyFeedback(
          mood: DreamMood.good,
          sleepScore: 5,
          factors: {SleepFactor.emotion},
        ),
      );
    }
    await first.close();
    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final records = await DriftStatisticsRepository(second)
        .watchRecords(StatisticsWindow(StatisticsPeriod.year, DateTime(2026)))
        .first;
    expect(records, hasLength(3)); // 包含上期，不含下一年；领域层再截取本期和今天。
    expect(records.every((r) => !r.hasContent), isTrue);
    final result = SleepFeedbackStatistics(
      window: StatisticsWindow(StatisticsPeriod.year, DateTime(2026)),
      records: records,
      today: DateTime(2026, 11, 12),
    );
    expect(result.goodCount, 2);
    expect(result.averageScore, 5);
    expect(result.topFactors, [SleepFactor.emotion]);
    expect(() => records.clear(), throwsUnsupportedError);
  });

  test('损坏的因素JSON上报读取失败，不伪装空反馈', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await DriftDreamRepository(
      database,
    ).save(date: DateTime(2026, 11, 12), content: '人工测试正文');
    await database.customStatement(
      "UPDATE dream_records SET sleep_factors = 'broken json'",
    );
    await expectLater(
      DriftStatisticsRepository(database)
          .watchRecords(
            StatisticsWindow(StatisticsPeriod.week, DateTime(2026, 11, 12)),
          )
          .first,
      throwsA(isA<FormatException>()),
    );
  });
}
