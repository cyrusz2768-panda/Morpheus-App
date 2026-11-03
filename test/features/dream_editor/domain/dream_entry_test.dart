import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

void main() {
  // `group` collects tests about the same unit. Test descriptions should read
  // like behavior, so a failure immediately explains what contract broke.
  group('DreamEntry date helpers', () {
    test('dateOnly removes the time of day', () {
      final result = DreamEntry.dateOnly(DateTime(2026, 9, 25, 23, 59));

      expect(result, DateTime(2026, 9, 25));
    });

    test('dateKey pads month and day to two digits', () {
      final result = DreamEntry.dateKey(DateTime(2026, 2, 3));

      expect(result, '2026-02-03');
    });
  });
}
