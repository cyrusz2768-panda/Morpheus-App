import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_calendar/data/drift_calendar_repository.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';

void main() {
  group('月历从真实 SQLite 派生日期标记', () {
    late AppDatabase database;
    late DriftDreamRepository editorRepository;
    late DriftCalendarRepository calendarRepository;

    setUp(() {
      // 只替换数据库的存放位置，不模拟 SQL、事务或 Drift 的变更通知。
      database = AppDatabase(NativeDatabase.memory());
      editorRepository = DriftDreamRepository(database);
      calendarRepository = DriftCalendarRepository(database);
    });

    tearDown(() => database.close());

    test('空月份返回只读空集合，不产生空记录', () async {
      final dates = await calendarRepository
          .watchRecordedDatesInMonth(DateTime(2026, 11))
          .first;

      expect(dates, isEmpty);
      expect(() => dates.add('2026-11-01'), throwsUnsupportedError);
      expect(await database.select(database.dreamRecords).get(), isEmpty);
    });

    test('当月首尾均包含，邻月排除，并忽略参数的日期与时刻', () async {
      for (final date in [
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 30),
        DateTime(2026, 12, 1),
      ]) {
        await editorRepository.save(date: date, content: '边界测试的梦');
      }

      final dates = await calendarRepository
          .watchRecordedDatesInMonth(DateTime(2026, 11, 23, 23, 59))
          .first;

      expect(dates, {'2026-11-01', '2026-11-30'});
      expect(() => dates.clear(), throwsUnsupportedError);
    });

    test('十二月到下一年一月的范围不会串月或混入同月的其他年份', () async {
      for (final date in [
        DateTime(2025, 12, 31),
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 1),
        DateTime(2027, 1, 31),
        DateTime(2027, 2, 1),
      ]) {
        await editorRepository.save(date: date, content: '跨年的梦');
      }

      expect(
        await calendarRepository
            .watchRecordedDatesInMonth(DateTime(2026, 12))
            .first,
        {'2026-12-01', '2026-12-31'},
      );
      expect(
        await calendarRepository
            .watchRecordedDatesInMonth(DateTime(2027, 1))
            .first,
        {'2027-01-01', '2027-01-31'},
      );
    });

    test('闰年二月包含 29 日，UTC 参数仍按其年月查询，不偏移到邻月', () async {
      for (final date in [
        DateTime(2028, 1, 31),
        DateTime(2028, 2, 1),
        DateTime(2028, 2, 29),
        DateTime(2028, 3, 1),
      ]) {
        await editorRepository.save(date: date, content: '闰年的梦');
      }

      expect(
        await calendarRepository
            .watchRecordedDatesInMonth(DateTime.utc(2028, 2, 29, 23, 59))
            .first,
        {'2028-02-01', '2028-02-29'},
      );
    });

    test('同一订阅随插入、修改和删除更新，无需重建仓库或刷新', () async {
      final iterator = StreamIterator(
        calendarRepository.watchRecordedDatesInMonth(DateTime(2026, 11)),
      );
      addTearDown(iterator.cancel);
      await _expectNextDates(iterator, {});

      final firstDate = DateTime(2026, 11, 3);
      await editorRepository.save(date: firstDate, content: '第一版');
      await _expectNextDates(iterator, {'2026-11-03'});

      // 修改正文只更新同一天的标记，不能因 upsert 生成重复日期或丢失圆点。
      await editorRepository.save(date: firstDate, content: '补充后的第二版');
      await _expectNextDates(iterator, {'2026-11-03'});

      final secondDate = DateTime(2026, 11, 4);
      await editorRepository.save(date: secondDate, content: '另外一天');
      await _expectNextDates(iterator, {'2026-11-03', '2026-11-04'});

      await editorRepository.deleteByDate(firstDate);
      await _expectNextDates(iterator, {'2026-11-04'});
      await editorRepository.deleteByDate(secondDate);
      await _expectNextDates(iterator, {});
    });

    test('过滤旧空白行，旧行变为有效正文或再次清空时立即改变标记', () async {
      // 旧版或外部导入可能留下正常 save 不允许的空白正文。直接写真实表，
      // 特意包含 SQLite 默认 TRIM 无法去掉的制表符、换行与 Unicode 空白。
      final blankContents = ['', '   ', '\n\t\u3000', '\u00a0\r\n'];
      for (var index = 0; index < blankContents.length; index += 1) {
        await database
            .into(database.dreamRecords)
            .insert(
              DreamRecordsCompanion.insert(
                dreamDate: '2026-11-0${index + 1}',
                content: blankContents[index],
                createdAtMillis: 0,
                updatedAtMillis: 0,
              ),
            );
      }
      await editorRepository.save(
        date: DateTime(2026, 11, 5),
        content: '  有正文的梦\n保留原有空白  ',
      );

      final iterator = StreamIterator(
        calendarRepository.watchRecordedDatesInMonth(DateTime(2026, 11)),
      );
      addTearDown(iterator.cancel);
      await _expectNextDates(iterator, {'2026-11-05'});

      await editorRepository.save(date: DateTime(2026, 11, 3), content: '补记的梦');
      await _expectNextDates(iterator, {'2026-11-03', '2026-11-05'});

      await (database.update(database.dreamRecords)
            ..where((table) => table.dreamDate.equals('2026-11-05')))
          .write(const DreamRecordsCompanion(content: Value('\n\t\u3000')));
      await _expectNextDates(iterator, {'2026-11-03'});

      // 派生查询只筛选显示，不擅自删改历史数据；实际空白行仍留在表中。
      expect(await database.select(database.dreamRecords).get(), hasLength(5));
    });
  });

  test('关闭并重开真实文件后，月历从已保存数据恢复而不依赖旧流缓存', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus_calendar_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/dreams.sqlite');

    await _withFileDatabase(file, (database) async {
      final editor = DriftDreamRepository(database);
      await editor.save(date: DateTime(2026, 12, 31), content: '跨年前的梦');
      await editor.save(date: DateTime(2027, 1, 1), content: '新年的梦');
      await editor.save(date: DateTime(2027, 1, 2), content: '随后删除');
      await editor.deleteByDate(DateTime(2027, 1, 2));
    });

    await _withFileDatabase(file, (database) async {
      final calendar = DriftCalendarRepository(database);
      expect(
        await calendar.watchRecordedDatesInMonth(DateTime(2026, 12)).first,
        {'2026-12-31'},
      );
      expect(
        await calendar.watchRecordedDatesInMonth(DateTime(2027, 1)).first,
        {'2027-01-01'},
      );
    });
  });
}

/// 等待真实数据库的下一个查询结果，不通过固定 sleep 猜测 SQL 的执行速度。
Future<void> _expectNextDates(
  StreamIterator<Set<String>> iterator,
  Set<String> expected,
) async {
  expect(
    await iterator.moveNext().timeout(const Duration(seconds: 10)),
    isTrue,
    reason: '数据库监听不应在页面仍订阅时提前结束',
  );
  expect(iterator.current, expected);
}

/// 每次调用均关闭连接后才返回，下一次调用无法复用上一份数据库或查询缓存。
Future<void> _withFileDatabase(
  File file,
  Future<void> Function(AppDatabase database) action,
) async {
  final database = AppDatabase(NativeDatabase(file));
  try {
    await action(database);
  } finally {
    await database.close();
  }
}
