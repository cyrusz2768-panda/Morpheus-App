import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_calendar/application/recorded_dream_dates_provider.dart';
import 'package:morpheus/features/dream_calendar/data/drift_calendar_repository.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';

void main() {
  test('正式 Provider 与编辑器复用数据库，保存及删除自动更新月历，邻月独立', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      // 仅替换数据库连接；月历与编辑器的正式 Repository 装配均真实运行。
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(() async {
      container.dispose();
      // overrideWithValue 不会运行原工厂的 onDispose，由测试明确释放连接。
      await database.close();
    });
    final november = DateTime(2026, 11);
    final december = DateTime(2026, 12);

    // 保持两个 family 实例的订阅，模拟翻月前后仍在使用的状态容器。
    // 监听器本身不负责把写入结果塞回 Provider；变化必须来自数据库流。
    final novemberSubscription = container.listen(
      recordedDreamDatesProvider(november),
      (previous, next) {},
    );
    final decemberSubscription = container.listen(
      recordedDreamDatesProvider(december),
      (previous, next) {},
    );
    addTearDown(novemberSubscription.close);
    addTearDown(decemberSubscription.close);

    expect(
      container.read(calendarRepositoryProvider),
      isA<DriftCalendarRepository>(),
    );
    expect(
      container.read(calendarRepositoryProvider),
      same(container.read(calendarRepositoryProvider)),
    );
    expect(
      await container.read(recordedDreamDatesProvider(november).future),
      isEmpty,
    );
    expect(
      await container.read(recordedDreamDatesProvider(december).future),
      isEmpty,
    );

    final editor = container.read(dreamRepositoryProvider);
    await editor.save(date: DateTime(2026, 11, 30), content: '十一月的最后一天');
    await _waitForDates(container, november, {'2026-11-30'});
    await _waitForDates(container, december, {});

    await editor.save(date: DateTime(2026, 12, 1), content: '十二月的第一天');
    await _waitForDates(container, december, {'2026-12-01'});
    await _waitForDates(container, november, {'2026-11-30'});

    await editor.deleteByDate(DateTime(2026, 11, 30));
    await _waitForDates(container, november, {});
    await _waitForDates(container, december, {'2026-12-01'});
  });
}

/// 等待指定快照，兼容 SQL 在监听前或监听后完成两种调度顺序。
/// 数据库错误立即让测试失败，不能被当作“没有圆点”悄悄略过。
Future<void> _waitForDates(
  ProviderContainer container,
  DateTime month,
  Set<String> expected,
) async {
  final ready = Completer<void>();
  final subscription = container.listen(recordedDreamDatesProvider(month), (
    previous,
    next,
  ) {
    if (ready.isCompleted) return;
    final error = next.asError;
    if (error != null) {
      ready.completeError(error.error, error.stackTrace);
      return;
    }
    final dates = next.asData?.value;
    if (dates != null &&
        dates.length == expected.length &&
        dates.containsAll(expected)) {
      ready.complete();
    }
  }, fireImmediately: true);
  try {
    await ready.future.timeout(const Duration(seconds: 10));
    expect(
      container.read(recordedDreamDatesProvider(month)).requireValue,
      expected,
    );
  } finally {
    subscription.close();
  }
}
