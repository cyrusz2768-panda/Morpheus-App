import 'package:flutter/foundation.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_editor/presentation/daily_feedback_text.dart';
import '../helpers/daily_record_test_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/l10n/app_text.dart';
import 'package:morpheus/l10n/generated/app_localizations_zh.dart';

import '../features/reminders/reminder_fakes.dart';

void main() {
  testWidgets('英文系统下保持中文，应用和标准组件加载同一语言资源', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dreamRepositoryProvider.overrideWithValue(InMemoryDreamRepository()),
          reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
          reminderNotificationsProvider.overrideWithValue(
            FakeReminderNotifications(),
          ),
        ],
        child: const MorpheusApp(),
      ),
    );
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    final context = tester.element(
      find.byKey(const Key('dream-content-field')),
    );
    expect(context.l10n.localeName, 'zh');
    expect(MaterialLocalizations.of(context).cancelButtonLabel, '取消');
    expect(find.text('夜行者'), findsOneWidget);
    expect(find.byTooltip('搜索梦境'), findsOneWidget);
    expect(AppLocalizations.supportedLocales, const [Locale('zh')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('每日反馈的名称、分隔符、评分和整句摘要都取自资源', (tester) async {
    // 用不同顺序的测试资源验证数据流，而不是重复断言正式中文常量。
    // 如果页面拼接中文标点或句子，这个用例就无法得到完整的注入结果。
    await tester.pumpWidget(
      MaterialApp(
        locale: morpheusLocale,
        localizationsDelegates: const [
          _DailyResourcesDelegate(),
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Text(
            context.l10n.dailyFeedbackSummary(
              moodLabel(context, DreamMood.good),
              context.l10n.dailyScoreValue(4),
              factorsLabel(
                context,
                const DailyFeedback(
                  factors: {SleepFactor.stress, SleepFactor.caffeine},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('score=4 points; factors=stress / caffeine; mood=good dream'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('Controller 不持有 Widget context，失败提示使用注入的资源', () async {
    final store = FakeReminderStore()..readFailures = 1;
    final container = ProviderContainer(
      overrides: [
        appLocalizationsProvider.overrideWithValue(_ErrorResources()),
        reminderSettingsStoreProvider.overrideWithValue(store),
        reminderNotificationsProvider.overrideWithValue(
          FakeReminderNotifications(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      reminderControllerProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    // build 会在 microtask 中加载；等待假存储的异步失败和状态更新。
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(reminderControllerProvider).error,
      'resource load failure',
    );
  });
}

class _ErrorResources extends AppLocalizationsZh {
  @override
  String get reminderLoadFailed => 'resource load failure';
}

class _DailyResources extends AppLocalizationsZh {
  @override
  String get dailyMoodGood => 'good dream';
  @override
  String get dailyFactorStress => 'stress';
  @override
  String get dailyFactorCaffeine => 'caffeine';
  @override
  String get dailyFactorsSeparator => ' / ';
  @override
  String dailyScoreValue(int score) => '$score points';
  @override
  String dailyFeedbackSummary(String mood, String score, String factors) =>
      'score=$score; factors=$factors; mood=$mood';
}

class _DailyResourcesDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _DailyResourcesDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'zh';
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(_DailyResources());
  @override
  bool shouldReload(_DailyResourcesDelegate old) => false;
}
