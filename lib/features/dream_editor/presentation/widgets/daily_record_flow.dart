import 'package:morpheus/features/dream_editor/presentation/daily_feedback_text.dart';
import 'package:flutter/material.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/l10n/app_text.dart';

/// 展示步骤只决定哪些输入可见，不持有另一份正文或反馈草稿。
/// 所有按钮仍经 Controller 保存后推进，页面重建不会清空已收起的文字。
class DailyRecordFlow extends StatelessWidget {
  const DailyRecordFlow({
    super.key,
    required this.state,
    required this.controller,
    required this.textController,
    this.navigationBusy = false,
  });

  final DreamEditorState state;
  final DreamEditorController controller;
  final TextEditingController textController;
  final bool navigationBusy;

  bool get enabled => state.canEdit && !state.isAdvancing && !navigationBusy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // 读取失败仍显示禁用编辑框和外层重试入口，不能把读取失败当作新的一天。
    if (!state.canEdit) return _content(context, expands: true);
    switch (state.step) {
      case DailyRecordStep.mood:
        return _question(context, l.dailyMoodQuestion, [
          for (final mood in DreamMood.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                key: Key('daily-mood-${mood.name}'),
                onPressed: enabled ? () => controller.chooseMood(mood) : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  backgroundColor: state.feedback.mood == mood
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.white,
                ),
                child: Text(moodLabel(context, mood)),
              ),
            ),
        ], () => controller.chooseMood(null));
      case DailyRecordStep.content:
        return LayoutBuilder(
          builder: (context, constraints) {
            final minimum = MediaQuery.textScalerOf(context).scale(200) + 160;
            final height = constraints.maxHeight < minimum
                ? minimum
                : constraints.maxHeight;
            return SingleChildScrollView(
              child: SizedBox(
                height: height,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _content(context, expands: true)),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('daily-content-next'),
                      onPressed: enabled
                          ? () {
                              FocusScope.of(context).unfocus();
                              controller.moveTo(DailyRecordStep.score);
                            }
                          : null,
                      child: Text(l.dailyContinue),
                    ),
                    _skip(context, () {
                      FocusScope.of(context).unfocus();
                      controller.moveTo(DailyRecordStep.score);
                    }),
                    TextButton(
                      key: const Key('daily-change-mood'),
                      onPressed: enabled
                          ? () => controller.moveTo(DailyRecordStep.mood)
                          : null,
                      child: Text(l.dailyMoodLabel),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      case DailyRecordStep.score:
        return _question(context, l.dailyScoreQuestion, [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (var score = 1; score <= 5; score++)
                ChoiceChip(
                  key: Key('daily-score-$score'),
                  label: Text(l.dailyScoreValue(score)),
                  selected: state.feedback.sleepScore == score,
                  onSelected: enabled
                      ? (_) => controller.chooseScore(score)
                      : null,
                ),
            ],
          ),
        ], controller.finishRecord);
      case DailyRecordStep.factors:
        return _question(
          context,
          l.dailyFactorsQuestion,
          [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final factor in SleepFactor.values)
                  FilterChip(
                    key: Key('daily-factor-${factor.name}'),
                    label: Text(factorLabel(context, factor)),
                    selected: state.feedback.factors.contains(factor),
                    onSelected: enabled
                        ? (selected) {
                            final factors = {...state.feedback.factors};
                            selected
                                ? factors.add(factor)
                                : factors.remove(factor);
                            controller.feedbackChanged(
                              state.feedback.copyWith(factors: factors),
                            );
                          }
                        : null,
                  ),
              ],
            ),
          ],
          controller.finishRecord,
          finish: true,
        );
      case DailyRecordStep.summary:
        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            key: const Key('daily-summary-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 普通屏幕上让正文从下半屏开始；大字号时按内容自然增长并可滚动。
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight * .42,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l.dailyFarewell,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(height: 1.6),
                    ),
                  ),
                ),
                _summaryRow(
                  context,
                  l.dailyMoodLabel,
                  moodLabel(context, state.feedback.mood),
                  DailyRecordStep.mood,
                ),
                if (state.feedback.hidesContent &&
                    state.content.trim().isNotEmpty)
                  ExpansionTile(
                    key: const Key('daily-hidden-content'),
                    title: Text(l.dailyHiddenDream),
                    children: [_content(context)],
                  )
                else if (!state.feedback.hidesContent)
                  _content(context),
                TextButton(
                  key: const Key('daily-edit-dream'),
                  onPressed: enabled
                      ? () => controller.moveTo(DailyRecordStep.content)
                      : null,
                  child: Text(l.dailyEditDream),
                ),
                const SizedBox(height: 20),
                _summaryRow(
                  context,
                  l.dailyScoreLabel,
                  state.feedback.sleepScore == null
                      ? l.dailyUnfilled
                      : l.dailyScoreValue(state.feedback.sleepScore!),
                  DailyRecordStep.score,
                ),
                _summaryRow(
                  context,
                  l.dailyFactorsLabel,
                  factorsLabel(context, state.feedback),
                  DailyRecordStep.factors,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
    }
  }

  Widget _summaryRow(
    BuildContext context,
    String title,
    String value,
    DailyRecordStep step,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(value),
    trailing: TextButton(
      key: Key('daily-edit-${step.name}'),
      onPressed: enabled ? () => controller.moveTo(step) : null,
      child: Text(context.l10n.dailyEdit),
    ),
  );

  Widget _content(BuildContext context, {bool expands = false}) => TextField(
    key: const Key('dream-content-field'),
    controller: textController,
    enabled: state.canEdit && !navigationBusy,
    onChanged: controller.contentChanged,
    expands: expands,
    minLines: expands ? null : 7,
    maxLines: null,
    textAlignVertical: TextAlignVertical.top,
    keyboardType: TextInputType.multiline,
    decoration: InputDecoration(
      labelText: context.l10n.dreamContentLabel,
      hintText: context.l10n.dreamContentHint,
    ),
  );

  Widget _skip(BuildContext context, VoidCallback action) => TextButton(
    key: const Key('daily-skip'),
    onPressed: enabled ? action : null,
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: .65),
      textStyle: Theme.of(context).textTheme.bodySmall,
    ),
    child: Text(context.l10n.dailySkip),
  );

  /// 底部按钮固定在本步骤下方；题目和选项可滚动，兼容窄屏和辅助大字号。
  Widget _question(
    BuildContext context,
    String title,
    List<Widget> children,
    VoidCallback skip, {
    bool finish = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 32),
              ...children,
            ],
          ),
        ),
      ),
      if (finish)
        FilledButton(
          key: const Key('daily-finish'),
          onPressed: enabled ? controller.finishRecord : null,
          child: Text(context.l10n.dailyFinish),
        ),
      _skip(context, skip),
    ],
  );
}
