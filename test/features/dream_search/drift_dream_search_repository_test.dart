import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';
import 'package:morpheus/features/dream_search/data/drift_dream_search_repository.dart';

void main() {
  group('临时内存数据库', () {
    late AppDatabase database;
    late DriftDreamRepository editor;
    late DriftDreamSearchRepository search;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      editor = DriftDreamRepository(database);
      search = DriftDreamSearchRepository(database);
    });
    tearDown(() => database.close());

    test('中文连续匹配按梦境日期倒序，保留正文和 UTC 时间，查询不改写原文', () async {
      const original = '  梦见海边\n一艘船 🌙  ';
      await editor.save(date: DateTime(2026, 11, 8), content: original);
      await editor.save(date: DateTime(2026, 11, 9), content: '海边的月光');
      // 最后写入旧日期，不能按更新时间排序。
      await editor.save(date: DateTime(2026, 10, 1), content: '海边散步');
      await editor.save(date: DateTime(2026, 11, 7), content: '山上的星星');

      final entries = await search.search('  海边  ');
      expect(entries.map((entry) => entry.id), [
        '2026-11-09',
        '2026-11-08',
        '2026-10-01',
      ]);
      expect(entries[1].content, original);
      expect(entries[1].createdAt.isUtc, isTrue);
      expect(entries[1].updatedAt.isUtc, isTrue);
      expect(
        (await editor.getByDate(DateTime(2026, 11, 8)))!.content,
        original,
      );
      expect(() => entries.clear(), throwsUnsupportedError);
      expect(await search.search('海船'), isEmpty);
      expect(await search.search('🌙'), hasLength(1));
      expect(await search.search('海边\n一艘'), hasLength(1));
    });

    test('英文忽略大小写；百分号、下划线、反斜线、引号和正则标点按字面匹配', () async {
      const content = r"Dream 100% a_b C:\dream (moon).* ' OR 1=1 --";
      await editor.save(date: DateTime(2026, 11, 8), content: content);
      await editor.save(date: DateTime(2026, 11, 9), content: 'Dream 1000 axb');
      expect(await search.search('dReAm'), hasLength(2));
      for (final term in ['%', '_', r'\', "' OR 1=1 --", '(moon).*']) {
        final entries = await search.search(term);
        expect(entries.map((entry) => entry.id), ['2026-11-08'], reason: term);
      }
      expect(await search.search('不存在'), isEmpty);
      expect(await editor.getAll(), hasLength(2));
    });

    test('空关键词不读取历史；更新或删除后重新搜索来自真实数据库', () async {
      final date = DateTime(2026, 11, 8);
      await editor.save(date: date, content: '月亮');
      expect(await search.search(''), isEmpty);
      expect(await search.search(' \n\t\u3000'), isEmpty);
      expect(await search.search('月亮'), hasLength(1));
      await editor.save(date: date, content: '太阳');
      expect(await search.search('月亮'), isEmpty);
      expect(await search.search('太阳'), hasLength(1));
      await editor.deleteByDate(date);
      expect(await search.search('太阳'), isEmpty);
      expect(database.schemaVersion, 4);
    });

    test('数据库读取失败向上传递，不伪装成无匹配', () async {
      // 只破坏本测试的独立内存表，稳定制造真正的 SQL 查询失败。
      // close 一个尚未打开的延迟连接不一定会让后续查询失败，不能以此模拟故障。
      await database.select(database.dreamRecords).get();
      await database.customStatement('DROP TABLE dream_records');
      expect(await search.search(' \n\t'), isEmpty);
      await expectLater(search.search('月亮'), throwsA(anything));
    });
  });

  test('关闭重开独立临时文件仍能搜索，无需新表或清除数据', () async {
    final directory = await Directory.systemTemp.createTemp('morpheus_search_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/test.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    try {
      await DriftDreamRepository(
        first,
      ).save(date: DateTime(2026, 11, 8), content: '持久化的月亮测试梦境');
    } finally {
      await first.close();
    }
    final reopened = AppDatabase(NativeDatabase(file));
    try {
      final result = await DriftDreamSearchRepository(reopened).search('月亮');
      expect(result.single.content, '持久化的月亮测试梦境');
    } finally {
      await reopened.close();
    }
  });
}
