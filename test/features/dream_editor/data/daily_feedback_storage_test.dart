import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_calendar/data/drift_calendar_repository.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_statistics/data/drift_statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

void main() {
  test('真实 v1 文件升级保留原文日期及时间，新字段未填写，反馈关闭重开后恢复', () async {
    final dir = await Directory.systemTemp.createTemp('morpheus_v2_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/upgrade.sqlite');
    var db = AppDatabase(
      NativeDatabase(
        file,
        setup: (old) {
          old.execute(
            'CREATE TABLE dream_records (dream_date TEXT NOT NULL PRIMARY KEY, content TEXT NOT NULL, created_at_millis INTEGER NOT NULL, updated_at_millis INTEGER NOT NULL)',
          );
          old.execute('PRAGMA user_version = 1');
          old.execute('INSERT INTO dream_records VALUES (?, ?, ?, ?)', [
            '2026-11-11',
            '  人工迁移测试\n原文 🌙  ',
            123456,
            234567,
          ]);
        },
      ),
    );
    var repo = DriftDreamRepository(db);
    try {
      final entry = (await repo.getAll()).single;
      expect(entry.content, '  人工迁移测试\n原文 🌙  ');
      expect(entry.id, '2026-11-11');
      expect(entry.createdAt.millisecondsSinceEpoch, 123456);
      expect(entry.updatedAt.millisecondsSinceEpoch, 234567);
      expect(entry.feedback.mood, isNull);
      expect(entry.feedback.sleepScore, isNull);
      expect(entry.feedback.factors, isEmpty);
      expect(entry.feedback.completed, isFalse);
      await repo.save(
        date: DateTime(2026, 11, 12),
        content: '',
        feedback: const DailyFeedback(
          mood: DreamMood.noDream,
          sleepScore: 4,
          factors: {SleepFactor.caffeine, SleepFactor.stress},
          completed: true,
        ),
      );
    } finally {
      await db.close();
    }
    db = AppDatabase(NativeDatabase(file));
    repo = DriftDreamRepository(db);
    try {
      final entry = (await repo.getByDate(DateTime(2026, 11, 12)))!;
      expect(entry.content, isEmpty);
      expect(entry.feedback.mood, DreamMood.noDream);
      expect(entry.feedback.sleepScore, 4);
      expect(entry.feedback.factors, {
        SleepFactor.caffeine,
        SleepFactor.stress,
      });
      expect(entry.feedback.completed, isTrue);
      expect(await repo.getAll(), hasLength(2));
    } finally {
      await db.close();
    }
  });

  for (final feedback in [
    const DailyFeedback(mood: DreamMood.forgotten),
    const DailyFeedback(sleepScore: 1),
    const DailyFeedback(factors: {SleepFactor.health}),
  ]) {
    test('无正文反馈可从历史和月历找回，保持旧统计正文口径 $feedback', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftDreamRepository(db);
      final date = DateTime(2026, 11, 12);
      await repo.save(date: date, content: '', feedback: feedback);
      expect(
        (await repo.getAll()).single.feedback.sleepScore,
        feedback.sleepScore,
      );
      expect(
        await DriftCalendarRepository(db).watchRecordedDatesInMonth(date).first,
        {'2026-11-12'},
      );
      expect(
        await DriftStatisticsRepository(db)
            .watchRecordedDates(StatisticsWindow(StatisticsPeriod.month, date))
            .first,
        isEmpty,
      );
      // 旧调用只编辑正文也不能覆盖已经填写的反馈。
      await repo.save(date: date, content: '人工正文');
      await repo.save(date: date, content: '');
      expect((await repo.getByDate(date))!.feedback.hasData, isTrue);
    });
  }

  test('并发正文更新不会用过时快照覆盖反馈，完成标记不进入历史和月历', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftDreamRepository(db);
    final date = DateTime(2026, 11, 12);
    await repo.save(
      date: date,
      content: '人工正文',
      feedback: const DailyFeedback(sleepScore: 1),
    );
    await Future.wait([
      repo.save(
        date: date,
        content: '人工正文',
        feedback: const DailyFeedback(sleepScore: 4),
      ),
      repo.save(date: date, content: '后续人工正文'),
    ]);
    expect((await repo.getByDate(date))!.feedback.sleepScore, 4);
    await repo.save(
      date: date,
      content: '',
      feedback: const DailyFeedback(completed: true),
    );
    expect((await repo.getByDate(date))!.feedback.completed, isTrue);
    expect(await repo.getAll(), isEmpty);
    expect(
      await DriftCalendarRepository(db).watchRecordedDatesInMonth(date).first,
      isEmpty,
    );
  });

  test('数据库拒绝 0 分和 6 分，未填写合法', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftDreamRepository(db);
    await repo.save(date: DateTime(2026, 11, 12), content: '人工测试');
    for (final score in [0, 6]) {
      await expectLater(
        db.customStatement('UPDATE dream_records SET sleep_score = ?', [score]),
        throwsA(anything),
      );
    }
    expect((await repo.getAll()).single.feedback.sleepScore, isNull);
  });
}
