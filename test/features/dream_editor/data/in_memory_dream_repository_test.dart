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
  });
}
