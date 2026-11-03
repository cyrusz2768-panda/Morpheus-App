import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// The storage contract required by the dream editor.
///
/// The UI depends on this interface rather than a concrete database. The
/// current skeleton uses an in-memory implementation for clarity; the next M1
/// step can add a Drift implementation without rewriting the page/controller.
abstract interface class DreamRepository {
  /// Reads the entry associated with [date], or returns null when none exists.
  Future<DreamEntry?> getByDate(DateTime date);

  /// Creates or updates the entry for [date].
  ///
  /// M1 permits one entry per local calendar day, so this operation behaves as
  /// an "upsert": update if present, insert otherwise.
  Future<DreamEntry> save({required DateTime date, required String content});

  /// Deletes the entry for [date]. Deleting a missing entry is harmless.
  Future<void> deleteByDate(DateTime date);
}
