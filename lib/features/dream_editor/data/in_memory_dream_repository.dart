import 'package:morpheus/features/dream_editor/data/dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// A small repository that stores data only while the process is running.
///
/// This is intentionally a teaching and testing implementation. It lets the
/// complete UI-to-storage flow run before database code is introduced. It is
/// NOT persistent: closing the app clears its map. 正式 App 已使用 Drift 实现；
/// 本类仅保留给不需要真实磁盘的快速测试和学习对比，不是默认的存储方式。
class InMemoryDreamRepository implements DreamRepository {
  InMemoryDreamRepository({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, DreamEntry> _entries = {};

  @override
  Future<DreamEntry?> getByDate(DateTime date) async {
    return _entries[DreamEntry.dateKey(date)];
  }

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
  }) async {
    final normalizedDate = DreamEntry.dateOnly(date);
    final key = DreamEntry.dateKey(normalizedDate);
    final existing = _entries[key];
    final nowUtc = _now().toUtc();

    final entry = DreamEntry(
      id: existing?.id ?? key,
      dreamDate: normalizedDate,
      content: content,
      createdAt: existing?.createdAt ?? nowUtc,
      updatedAt: nowUtc,
    );

    _entries[key] = entry;
    return entry;
  }

  @override
  Future<void> deleteByDate(DateTime date) async {
    _entries.remove(DreamEntry.dateKey(date));
  }
}
