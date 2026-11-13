import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/theme.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'package:morpheus/features/dream_statistics/application/statistics_provider.dart';
import 'package:morpheus/features/dream_statistics/data/statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';
import 'package:morpheus/features/dream_statistics/domain/sleep_feedback_statistics.dart';
import 'package:morpheus/features/dream_statistics/presentation/dream_statistics_page.dart';
import 'package:morpheus/features/dream_statistics/presentation/feedback_statistics_content.dart';
import 'package:morpheus/l10n/app_text.dart';
import 'package:morpheus/l10n/generated/app_localizations_zh.dart';

void main() {
  late _Repository repository;
  setUp(() => repository = _Repository());
  tearDown(() => repository.changes.close());
  Future<void> show(
    WidgetTester tester, {
    double scale = 1,
    DateTime? today,
    AppLocalizations? resources,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statisticsRepositoryProvider.overrideWithValue(repository),
          dreamRepositoryProvider.overrideWithValue(InMemoryDreamRepository()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          locale: morpheusLocale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            if (resources != null) _ResourcesDelegate(resources),
            ...AppLocalizations.localizationsDelegates,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: DreamStatisticsPage(now: () => today ?? DateTime(2026, 11, 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Future<void> scroll(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(
      find.byKey(Key(key)),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  StatisticsRecord record(
    int day, {
    DreamMood? mood,
    int? score,
    Set<SleepFactor> factors = const {},
  }) => StatisticsRecord(
    date: DateTime(2026, 11, day),
    hasContent: false,
    feedback: DailyFeedback(mood: mood, sleepScore: score, factors: factors),
  );

  testWidgets('空周期为灰色未知，评分不是0，不展示记录天数或次数', (tester) async {
    await show(tester);
    expect(find.textContaining('还没有明确的好梦或噩梦反馈'), findsOneWidget);
    expect(
      find.byKey(const Key('statistics-week-status-grid')),
      findsOneWidget,
    );
    final cells = tester.widgetList<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.key.toString().contains('statistics-week-cell-'),
      ),
    );
    expect(cells, hasLength(28));
    expect(
      cells.every(
        (cell) =>
            (cell.decoration! as BoxDecoration).color == Colors.transparent,
      ),
      isTrue,
    );
    expect(find.text('记录天数'), findsNothing);
    expect(find.textContaining(' 天'), findsNothing);
    expect(find.byKey(const Key('statistics-dream-ratio')), findsNothing);
    await scroll(tester, 'statistics-score-average');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('statistics-score-average')))
          .data,
      '—',
    );
    expect(find.textContaining('NaN'), findsNothing);
    await scroll(tester, 'statistics-factors-summary');
    expect(find.textContaining('尚未填写影响因素。'), findsOneWidget);
  });
  testWidgets('五类颜色分开，比例互补，定性只依据显式状态', (tester) async {
    repository.records = [
      record(9, mood: DreamMood.good),
      record(10, mood: DreamMood.nightmare),
    ];
    await show(tester);
    expect(find.textContaining('频率差不多。'), findsOneWidget);
    expect(find.text('好梦 50% · 噩梦 50%'), findsOneWidget);
    expect(
      statusColor(DreamStatusCategory.noDream),
      isNot(statusColor(DreamStatusCategory.unfilled)),
    );
    expect(DreamStatusCategory.values.map(statusColor).toSet(), hasLength(5));
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CustomPaint>(find.byKey(const Key('statistics-status-chart')))
          .painter,
      isA<StatusRingPainter>(),
    );
    for (final category in DreamStatusCategory.values) {
      final dot = tester.widget<Container>(
        find.byKey(Key('statistics-status-${category.name}')),
      );
      expect((dot.decoration! as BoxDecoration).color, statusColor(category));
    }
  });
  testWidgets('名称、定性整句、评分和因素摘要由注入资源提供', (tester) async {
    repository.records = [
      record(9, mood: DreamMood.good, score: 4, factors: {SleepFactor.stress}),
    ];
    await show(tester, resources: _StatisticsResources());
    expect(find.text('test mood 本周 / allGood'), findsOneWidget);
    await scroll(tester, 'statistics-score-average');
    expect(find.text('test average 4.0'), findsOneWidget);
    await scroll(tester, 'statistics-factors-summary');
    expect(find.text('test factors 本周 / pressure /  / '), findsOneWidget);
  });
  testWidgets('月年切换、历史称呼、未来禁用和回到本期', (tester) async {
    await show(tester);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('statistics-next')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);
    await tester.tap(find.byKey(const Key('statistics-previous')));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月'), findsOneWidget);
    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('statistics-previous')));
    await tester.pumpAndSettle();
    expect(find.text('2025年'), findsOneWidget);
    expect(find.textContaining('这一年还没有'), findsOneWidget);
    await tester.tap(find.byKey(const Key('statistics-current')));
    await tester.pumpAndSettle();
    expect(find.text('2026年'), findsOneWidget);
    expect(find.textContaining('今年还没有'), findsOneWidget);
  });
  testWidgets('读取失败隐藏整份旧快照，重试和修改反馈会实时更新', (tester) async {
    repository.records = [record(9, mood: DreamMood.good, score: 5)];
    await show(tester);
    repository.changes.addError(StateError('测试读取失败'));
    await tester.pumpAndSettle();
    expect(find.text('统计读取失败，请重试。'), findsOneWidget);
    expect(find.byKey(const Key('statistics-status-chart')), findsNothing);
    expect(find.byKey(const Key('statistics-score-average')), findsNothing);
    await tester.tap(find.byKey(const Key('statistics-retry')));
    await tester.pumpAndSettle();
    expect(find.textContaining('都是好梦。'), findsOneWidget);
    repository.changes.add([record(9, mood: DreamMood.nightmare, score: 1)]);
    await tester.pumpAndSettle();
    expect(find.textContaining('都是噩梦。'), findsOneWidget);
    await scroll(tester, 'statistics-score-average');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('statistics-score-average')))
          .data,
      '1.0 / 5 分',
    );
  });
  testWidgets('因素只写前三项不列数字，少于三项不虚构', (tester) async {
    repository.records = [
      record(
        9,
        factors: {
          SleepFactor.stress,
          SleepFactor.emotion,
          SleepFactor.news,
          SleepFactor.caffeine,
        },
      ),
    ];
    await show(tester);
    await scroll(tester, 'statistics-factors-summary');
    expect(find.text('本周你认为对睡眠影响较大的是压力、情绪和时事。'), findsOneWidget);
    expect(find.text('咖啡因'), findsNothing);
    expect(find.textContaining('次'), findsNothing);
  });
  testWidgets('不确定反馈采用专门句式，未来评分与已过缺值读屏区分', (tester) async {
    repository.records = [
      record(9, factors: {SleepFactor.unsure}),
    ];
    await show(tester);
    await scroll(tester, 'statistics-score-chart');
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics && (w.properties.label?.contains('尚未开始') ?? false),
      ),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label?.contains('未填写') ?? false),
      ),
      findsWidgets,
    );
    await scroll(tester, 'statistics-factors-summary');
    expect(find.text('本周你还不确定哪些因素影响了睡眠。'), findsOneWidget);
    expect(find.textContaining('影响较大的是不确定'), findsNothing);
  });

  testWidgets('周状态网格按星期和状态着色，未记录与未来不着色，月年保持环图', (tester) async {
    repository.records = [
      record(9, mood: DreamMood.good),
      record(10, mood: DreamMood.nightmare),
      record(11, mood: DreamMood.forgotten),
      record(12, mood: DreamMood.noDream),
      record(13, mood: DreamMood.good),
    ];
    await show(tester, today: DateTime(2026, 11, 12));
    for (var day = 9; day <= 15; day++) {
      var filled = 0;
      for (final mood in DreamMood.values) {
        final cell = tester.widget<Container>(
          find.byKey(Key('statistics-week-cell-2026-11-$day-${mood.name}')),
        );
        final color = (cell.decoration! as BoxDecoration).color;
        final expected = day <= 12 && mood.index == day - 9;
        expect(
          color,
          expected
              ? statusColor(DreamStatusCategory.values.byName(mood.name))
              : Colors.transparent,
        );
        if (color != Colors.transparent) filled++;
      }
      expect(filled, day <= 12 ? 1 : 0);
    }
    for (final period in ['月', '年']) {
      await tester.tap(find.text(period));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('statistics-week-status-grid')),
        findsNothing,
      );
      expect(
        tester
            .widget<CustomPaint>(
              find.byKey(const Key('statistics-status-chart')),
            )
            .painter,
        isA<StatusRingPainter>(),
      );
    }
  });

  for (final period in ['周', '月', '年']) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('$period 图在320宽/$scale字号下完整显示，无横向滚动', (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        repository.records = [
          record(
            9,
            score: 5,
            mood: DreamMood.good,
            factors: {SleepFactor.stress},
          ),
        ];
        await show(tester, scale: scale);
        if (period != '周') {
          await tester.tap(find.text(period));
          await tester.pumpAndSettle();
        }
        if (period == '周') {
          final grid = tester.getRect(
            find.byKey(const Key('statistics-week-status-grid')),
          );
          expect(grid.left, greaterThanOrEqualTo(0));
          expect(grid.right, lessThanOrEqualTo(320));
        }
        await scroll(tester, 'statistics-score-chart');
        final chart = tester.getRect(
          find.byKey(const Key('statistics-score-chart')),
        );
        expect(chart.left, greaterThanOrEqualTo(0));
        expect(chart.right, lessThanOrEqualTo(320));
        expect(
          tester
              .widgetList<Scrollable>(find.byType(Scrollable))
              .where(
                (w) =>
                    w.axisDirection == AxisDirection.left ||
                    w.axisDirection == AxisDirection.right,
              ),
          isEmpty,
        );
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const Key('statistics-score-chart')),
                    )
                    .painter!
                as ScoreTrendPainter;
        expect(
          painter.values,
          hasLength(
            period == '周'
                ? 7
                : period == '月'
                ? 5
                : 12,
          ),
        );
        if (period == '月') {
          for (final tick in ['1–7', '8–14', '15–21', '22–28', '29–30']) {
            expect(find.text(tick), findsOneWidget);
          }
        }
        await scroll(tester, 'statistics-factors-summary');
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _Repository implements IStatisticsRepository {
  List<StatisticsRecord> records = [];
  final changes = StreamController<List<StatisticsRecord>>.broadcast();
  @override
  Stream<List<StatisticsRecord>> watchRecords(StatisticsWindow window) async* {
    yield records;
    yield* changes.stream;
  }

  @override
  Stream<Set<String>> watchRecordedDates(StatisticsWindow window) =>
      watchRecords(window).map(
        (rows) => rows
            .where((r) => r.hasContent)
            .map((r) => '${r.date.year}-${r.date.month}-${r.date.day}')
            .toSet(),
      );
}

class _StatisticsResources extends AppLocalizationsZh {
  @override
  String statisticsMoodInsight(String scope, String insight) =>
      'test mood $scope / $insight';
  @override
  String statisticsAverageScore(String score) => 'test average $score';
  @override
  String get dailyFactorStress => 'pressure';
  @override
  String statisticsFactorsSummary(
    String scope,
    int count,
    String first,
    String second,
    String third,
  ) => 'test factors $scope / $first / $second / $third';
}

class _ResourcesDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _ResourcesDelegate(this.resources);
  final AppLocalizations resources;
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'zh';
  @override
  Future<AppLocalizations> load(Locale locale) async => resources;
  @override
  bool shouldReload(_ResourcesDelegate old) => old.resources != resources;
}
