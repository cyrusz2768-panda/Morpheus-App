import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';

/// An immutable record of one day's dream.
///
/// Domain objects describe the application's meaning without knowing anything
/// about Flutter widgets, SQLite, HTTP or the operating system. That separation
/// is important: the same DreamEntry can later be stored by Drift, exported to
/// a PDF, or sent to an explicitly authorized AI service.
class DreamEntry {
  const DreamEntry({
    required this.id,
    required this.dreamDate,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.feedback = const DailyFeedback(),
    this.images = const [],
  });

  /// Stable identifier of this record.
  ///
  /// M1 每天只有一条记录，内存实现与 SQLite 实现均使用 yyyy-mm-dd 日期键。
  /// 数据库对日期主键建立唯一约束；将来一天多条记录时再设计独立 ID 与迁移。
  final String id;

  /// The local calendar day to which the dream belongs.
  ///
  /// Only year, month and day are meaningful. Use [dateOnly] before comparing
  /// dates so that 09:00 and 22:00 on the same day are treated as one day.
  final DateTime dreamDate;

  /// Text written by the user.
  ///
  /// Whitespace inside the text is preserved. `trim()` is used only to decide
  /// whether an entry is empty.
  final String content;

  final DailyFeedback feedback;
  final List<DreamImage> images;
  bool get hasData =>
      content.trim().isNotEmpty || images.isNotEmpty || feedback.hasData;

  /// UTC instant at which the record was first created.
  final DateTime createdAt;

  /// UTC instant at which the record was most recently saved.
  final DateTime updatedAt;

  /// Returns a new instance with selected fields replaced.
  ///
  /// Immutable objects are safer than objects modified in place: old UI states
  /// remain trustworthy, which makes Riverpod updates and tests predictable.
  DreamEntry copyWith({
    String? id,
    DateTime? dreamDate,
    String? content,
    DailyFeedback? feedback,
    List<DreamImage>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DreamEntry(
      id: id ?? this.id,
      dreamDate: dreamDate ?? this.dreamDate,
      content: content ?? this.content,
      feedback: feedback ?? this.feedback,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Removes the time-of-day component from a local [DateTime].
  static DateTime dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  /// Produces a stable `yyyy-mm-dd` key without adding a date-format package.
  static String dateKey(DateTime value) {
    final date = dateOnly(value);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
