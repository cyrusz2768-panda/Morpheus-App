import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';

void main() {
  group('InMemoryDreamRepository', () {
    // A fixed clock prevents a test from changing based on the real current
    // time. Deterministic tests are easier to reproduce and debug.
    final fixedNow = DateTime.utc(2026, 9, 25, 10);

    test('creates and reads one entry for a date', () async {
      final repository = InMemoryDreamRepository(now: () => fixedNow);
      final date = DateTime(2026, 9, 25);

      await repository.save(date: date, content: '在海面上行走');
      final result = await repository.getByDate(date);

      expect(result, isNotNull);
      expect(result!.content, '在海面上行走');
      expect(result.createdAt, fixedNow);
    });

    test('updates instead of duplicating the same day', () async {
      final repository = InMemoryDreamRepository(now: () => fixedNow);
      final morning = DateTime(2026, 9, 25, 8);
      final evening = DateTime(2026, 9, 25, 20);

      final first = await repository.save(date: morning, content: '第一版');
      final second = await repository.save(date: evening, content: '修改版');

      expect(second.id, first.id);
      expect(second.content, '修改版');
      expect((await repository.getByDate(morning))?.content, '修改版');
    });

    test('deletes an existing entry', () async {
      final repository = InMemoryDreamRepository(now: () => fixedNow);
      final date = DateTime(2026, 9, 25);

      await repository.save(date: date, content: '即将删除');
      await repository.deleteByDate(date);

      expect(await repository.getByDate(date), isNull);
    });

    test('空仓库的历史是空列表', () async {
      final repository = InMemoryDreamRepository(now: () => fixedNow);

      expect(await repository.getAll(), isEmpty);
    });

    test('历史按梦境日期倒序，跨月跨年也不依赖插入顺序', () async {
      final repository = InMemoryDreamRepository(now: () => fixedNow);
      await repository.save(date: DateTime(2026, 1, 2), content: '最早的梦');
      await repository.save(date: DateTime(2027, 1, 1), content: '最新的梦');
      await repository.save(date: DateTime(2026, 12, 31), content: '跨年前的梦');

      final history = await repository.getAll();

      expect(history.map((entry) => entry.id), [
        '2027-01-01',
        '2026-12-31',
        '2026-01-02',
      ]);
    });

    test('修改旧日期不增加历史条目，也不改变它的日期位置', () async {
      final repository = InMemoryDreamRepository(now: () => fixedNow);
      final oldDate = DateTime(2026, 9, 24);
      await repository.save(date: oldDate, content: '旧日期的第一版');
      await repository.save(date: DateTime(2026, 9, 25), content: '最近一天的梦');
      await repository.save(date: oldDate, content: '旧日期补充后的正文');

      final history = await repository.getAll();

      expect(history, hasLength(2));
      expect(history.first.id, '2026-09-25');
      expect(history.last.content, '旧日期补充后的正文');
    });

    test('历史排除纯空白，删除后仅移除对应日期', () async {
      final repository = InMemoryDreamRepository(now: () => fixedNow);
      final removedDate = DateTime(2026, 9, 24);
      await repository.save(date: removedDate, content: '稍后删除');
      await repository.save(date: DateTime(2026, 9, 25), content: '  保留首尾空格  ');

      // 模拟旧版本留下的空记录；历史查询不能把它展示成一条有效梦境。
      await repository.save(date: DateTime(2026, 9, 26), content: '\n\t\u3000');
      await repository.deleteByDate(removedDate);

      final history = await repository.getAll();

      expect(history, hasLength(1));
      expect(history.single.id, '2026-09-25');
      expect(history.single.content, '  保留首尾空格  ');
    });
  });
}
