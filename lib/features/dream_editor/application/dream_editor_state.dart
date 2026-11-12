import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';

enum DailyRecordStep { mood, content, score, factors, summary }

/// High-level status of the current editor save operation.
enum DreamSaveStatus {
  /// No edits are waiting to be saved.
  idle,

  /// The user has changed the text and the debounce timer is running.
  unsaved,

  /// A repository write is currently in progress.
  saving,

  /// The displayed content was saved successfully.
  saved,

  /// The last save failed; [DreamEditorState.errorMessage] explains why.
  failed,
}

/// 区分“从磁盘读取失败”和“把草稿写入磁盘失败”。
///
/// 二者都可以显示“重试”，但不能执行同一个动作：读取失败时重新读取；
/// 保存失败时只能重写当前草稿，否则重新加载旧记录会覆盖用户还没存好的文字。
enum DreamEditorFailure { load, save }

/// Immutable state rendered by the dream editor page.
///
/// The page does not guess whether data is loading or saved. It simply renders
/// this value, while DreamEditorController owns transitions between states.
class DreamEditorState {
  const DreamEditorState({
    required this.date,
    this.content = '',
    this.feedback = const DailyFeedback(),
    this.step = DailyRecordStep.mood,
    this.isAdvancing = false,
    this.isLoading = true,
    this.saveStatus = DreamSaveStatus.idle,
    this.errorMessage,
    this.failure,
  });

  final DateTime date;
  final String content;
  final DailyFeedback feedback;
  final DailyRecordStep step;
  final bool isAdvancing;
  final bool isLoading;
  final DreamSaveStatus saveStatus;
  final String? errorMessage;
  final DreamEditorFailure? failure;

  /// 数据没有成功读出前，空白编辑框不代表“数据库里没有记录”。
  /// 此时禁止编辑，避免把磁盘上的既有梦境误当成空记录覆盖或删除。
  bool get canEdit => !isLoading && failure != DreamEditorFailure.load;

  /// 页面进入后台时可以据此尝试尽快提交草稿。
  /// 正在保存也算未完成，不能把“请求已经发出”误认为“已经写入磁盘”。
  bool get hasPendingSave =>
      canEdit &&
      (saveStatus == DreamSaveStatus.unsaved ||
          saveStatus == DreamSaveStatus.saving ||
          failure == DreamEditorFailure.save);

  DreamEditorState copyWith({
    DateTime? date,
    String? content,
    DailyFeedback? feedback,
    DailyRecordStep? step,
    bool? isAdvancing,
    bool? isLoading,
    DreamSaveStatus? saveStatus,
    String? errorMessage,
    DreamEditorFailure? failure,
    bool clearError = false,
  }) {
    return DreamEditorState(
      date: date ?? this.date,
      content: content ?? this.content,
      feedback: feedback ?? this.feedback,
      step: step ?? this.step,
      isAdvancing: isAdvancing ?? this.isAdvancing,
      isLoading: isLoading ?? this.isLoading,
      saveStatus: saveStatus ?? this.saveStatus,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      // “清除错误”必须同时清除错误类型，不能只把提示文字隐藏。
      failure: clearError ? null : failure ?? this.failure,
    );
  }
}
