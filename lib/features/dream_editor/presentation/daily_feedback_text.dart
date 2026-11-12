import 'package:flutter/material.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/l10n/app_text.dart';

/// 编辑器与历史共用反馈名称；存储层只认识稳定标识，不参与中文展示。
String moodLabel(BuildContext context, DreamMood? mood) => switch (mood) {
  DreamMood.good => context.l10n.dailyMoodGood,
  DreamMood.nightmare => context.l10n.dailyMoodNightmare,
  DreamMood.forgotten => context.l10n.dailyMoodForgotten,
  DreamMood.noDream => context.l10n.dailyMoodNoDream,
  null => context.l10n.dailyUnfilled,
};

String factorLabel(BuildContext context, SleepFactor factor) =>
    switch (factor) {
      SleepFactor.stress => context.l10n.dailyFactorStress,
      SleepFactor.emotion => context.l10n.dailyFactorEmotion,
      SleepFactor.news => context.l10n.dailyFactorNews,
      SleepFactor.travel => context.l10n.dailyFactorTravel,
      SleepFactor.screen => context.l10n.dailyFactorScreen,
      SleepFactor.caffeine => context.l10n.dailyFactorCaffeine,
      SleepFactor.schedule => context.l10n.dailyFactorSchedule,
      SleepFactor.environment => context.l10n.dailyFactorEnvironment,
      SleepFactor.health => context.l10n.dailyFactorHealth,
      SleepFactor.unsure => context.l10n.dailyFactorUnsure,
    };

String factorsLabel(BuildContext context, DailyFeedback feedback) =>
    feedback.factors.isEmpty
    ? context.l10n.dailyUnfilled
    : SleepFactor.values
          .where(feedback.factors.contains)
          .map((e) => factorLabel(context, e))
          .join(context.l10n.dailyFactorsSeparator);
