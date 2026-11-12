/// 稳定标识用于本地存储，中文名称由界面资源提供，避免改文案影响旧记录。
enum DreamMood { good, nightmare, forgotten, noDream }

enum SleepFactor {
  stress,
  emotion,
  news,
  travel,
  screen,
  caffeine,
  schedule,
  environment,
  health,
  unsure,
}

/// 主观反馈与正文分别表达不同信息；没有评分用 null，绝不能用 0 代替。
/// completed 单独保存以便重开仍显示结束页；“全部跳过”不进入历史与日历。
class DailyFeedback {
  const DailyFeedback({
    this.mood,
    this.sleepScore,
    this.factors = const {},
    this.completed = false,
  }) : assert(sleepScore == null || (sleepScore >= 1 && sleepScore <= 5));

  final DreamMood? mood;
  final int? sleepScore;
  final Set<SleepFactor> factors;
  final bool completed;

  bool get hasData => mood != null || sleepScore != null || factors.isNotEmpty;
  bool get hidesContent =>
      mood == DreamMood.forgotten || mood == DreamMood.noDream;

  DailyFeedback copyWith({
    DreamMood? mood,
    int? sleepScore,
    Set<SleepFactor>? factors,
    bool? completed,
    bool clearMood = false,
    bool clearScore = false,
  }) => DailyFeedback(
    mood: clearMood ? null : mood ?? this.mood,
    sleepScore: clearScore ? null : sleepScore ?? this.sleepScore,
    factors: factors == null ? this.factors : Set.unmodifiable(factors),
    completed: completed ?? this.completed,
  );
}
