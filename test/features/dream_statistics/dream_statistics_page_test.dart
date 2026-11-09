import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/theme.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_statistics/application/statistics_provider.dart';
import 'package:morpheus/features/dream_statistics/data/statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';
import 'package:morpheus/features/dream_statistics/presentation/dream_statistics_page.dart';
import 'package:morpheus/l10n/app_text.dart';

void main() {
  late _Repository repository;
  setUp(() => repository = _Repository());
  tearDown(() => repository.changes.close());

  Future<void> show(WidgetTester tester, {double scale = 1}) async {
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: DreamStatisticsPage(now: () => DateTime(2026, 11, 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('空周期显示空态和无占比，不出现NaN或虚构分类', (tester) async {
    await show(tester);
    expect(find.text('0 天'), findsOneWidget);
    expect(find.byKey(const Key('statistics-empty')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('双休日'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0 天 · —'), findsNWidgets(2));
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('噩梦'), findsNothing);
  });

  testWidgets('月年切换和翻期正确，未来周期禁用，返回本期', (tester) async {
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
    expect(find.text('2026年'), findsOneWidget);
    await tester.tap(find.byKey(const Key('statistics-previous')));
    await tester.pumpAndSettle();
    expect(find.text('2025年'), findsOneWidget);
    await tester.tap(find.byKey(const Key('statistics-current')));
    await tester.pumpAndSettle();
    expect(find.text('2026年'), findsOneWidget);
  });

  testWidgets('订阅出错隐藏旧统计，重试后恢复，实时日期变更更新', (tester) async {
    repository.dates = {'2026-11-09'};
    await show(tester);
    expect(find.text('1 天'), findsOneWidget);
    repository.changes.addError(StateError('测试读取失败'));
    await tester.pumpAndSettle();
    expect(find.text('统计读取失败，请重试。'), findsOneWidget);
    expect(find.byKey(const Key('statistics-recorded-days')), findsNothing);
    await tester.tap(find.byKey(const Key('statistics-retry')));
    await tester.pumpAndSettle();
    expect(find.text('1 天'), findsOneWidget);
    repository.changes.add({'2026-11-09', '2026-11-10'});
    await tester.pumpAndSettle();
    expect(find.text('2 天'), findsOneWidget);
  });

  testWidgets('窄屏大字号年视图可滚动，无布局溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, scale: 2);
    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('记录趋势'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(-1500, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('比例四舍五入后仍合计100%', (tester) async {
    repository.dates = {
      '2026-11-01',
      '2026-11-02',
      '2026-11-03',
      '2026-11-04',
      '2026-11-05',
      '2026-11-06',
      '2026-11-09',
      '2026-11-10',
    };
    await show(tester);
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('双休日'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1 天 · 13%'), findsOneWidget);
    expect(find.text('7 天 · 87%'), findsOneWidget);
  });
}

class _Repository implements IStatisticsRepository {
  Set<String> dates = {};
  final changes = StreamController<Set<String>>.broadcast();
  @override
  Stream<Set<String>> watchRecordedDates(StatisticsWindow window) async* {
    yield dates;
    yield* changes.stream;
  }
}
