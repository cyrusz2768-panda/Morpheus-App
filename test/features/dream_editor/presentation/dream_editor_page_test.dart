import '../../../helpers/daily_record_test_helper.dart';
import 'package:morpheus/features/dream_editor/domain/daily_feedback.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_editor/presentation/dream_editor_page.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/l10n/app_text.dart';

import '../../reminders/reminder_fakes.dart';

void main() {
  testWidgets('typing saves the current dream after the debounce delay', (
    tester,
  ) async {
    final repository = InMemoryDreamRepository();

    await tester.pumpWidget(
      ProviderScope(
        // Provider overrides are dependency injection for tests. The page uses
        // this exact repository, allowing the test to inspect saved data.
        overrides: [
          dreamRepositoryProvider.overrideWithValue(repository),
          reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
          reminderNotificationsProvider.overrideWithValue(
            FakeReminderNotifications(),
          ),
        ],
        child: const MaterialApp(
          locale: morpheusLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DreamEditorPage(),
        ),
      ),
    );

    // Finish the controller's asynchronous initial read.
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);

    const dream = '我梦见一座漂浮在云上的图书馆。';
    await tester.enterText(find.byKey(const Key('dream-content-field')), dream);

    // enterText changes the controller immediately, while Flutter paints the
    // resulting Riverpod state on the next frame.
    await tester.pump();
    expect(find.text('等待自动保存'), findsOneWidget);

    // The controller deliberately waits 800 ms after the last keystroke.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);

    final saved = await repository.getByDate(DateTime.now());
    expect(saved?.content, dream);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('保存失败点击重试，输入框保留草稿并重新保存而不是重读旧记录', (tester) async {
    final repository = _FaultInjectingRepository();
    await repository.save(date: DateTime.now(), content: '数据库旧文字');
    repository.saveFailures = 1;
    await _showEditor(tester, repository);

    const draft = '不能被旧记录覆盖的新草稿';
    await tester.enterText(find.byKey(const Key('dream-content-field')), draft);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text(draft), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);

    expect(find.text(draft), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
    expect((await repository.getByDate(DateTime.now()))?.content, draft);
  });

  testWidgets('读取失败禁用输入框，点击重试成功后才允许修改旧梦境', (tester) async {
    final repository = _FaultInjectingRepository();
    await repository.save(date: DateTime.now(), content: '磁盘上实际存在的内容');
    repository.readFailures = 1;
    await _showEditor(tester, repository);

    final field = find.byKey(const Key('dream-content-field'));
    expect(tester.widget<TextField>(field).enabled, isFalse);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);

    expect(tester.widget<TextField>(field).enabled, isTrue);
    expect(find.text('磁盘上实际存在的内容'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('还没等到防抖时间就进入后台，会立刻提交草稿', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final repository = InMemoryDreamRepository();
    await _showEditor(tester, repository);

    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '离开 App 前最后输入的文字',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(await repository.getByDate(DateTime.now()), isNull);

    // 只经过了 100 ms，若保存成功，只可能是生命周期触发，而非 800 ms 计时器。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(
      (await repository.getByDate(DateTime.now()))?.content,
      '离开 App 前最后输入的文字',
    );
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('进入后台时立即提交最新草稿，即使旧文字仍在异步写入中', (tester) async {
    // 测试生命周期时显式恢复 resumed，避免把 inactive 状态留给下一项测试。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    final repository = _FaultInjectingRepository();
    await _showEditor(tester, repository);
    final field = find.byKey(const Key('dream-content-field'));
    final gate = Completer<void>();
    repository.nextSaveGate = gate;

    await tester.enterText(field, '仍然在写入的第一版');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(find.text('正在保存'), findsOneWidget);

    await tester.enterText(field, '进入后台前输入的最后一版');
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    gate.complete();
    await tester.pumpAndSettle();
    await openDreamTextIfPrompted(tester);

    expect(
      (await repository.getByDate(DateTime.now()))?.content,
      '进入后台前输入的最后一版',
    );
    expect(find.text('已保存'), findsOneWidget);
  });
}

/// Widget 测试只关心页面交互；用内存仓库控制错误，不依赖真机插件或磁盘环境。
Future<void> _showEditor(
  WidgetTester tester,
  InMemoryDreamRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(repository),
        reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
        reminderNotificationsProvider.overrideWithValue(
          FakeReminderNotifications(),
        ),
      ],
      child: const MaterialApp(
        locale: morpheusLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DreamEditorPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openDreamTextIfPrompted(tester);
}

/// 在一次读/写操作上注入故障或延迟，使错误处理测试可以稳定重复。
class _FaultInjectingRepository extends InMemoryDreamRepository {
  int saveFailures = 0;
  int readFailures = 0;
  Completer<void>? nextSaveGate;

  @override
  Future<DreamEntry?> getByDate(DateTime date) async {
    if (readFailures > 0) {
      readFailures -= 1;
      throw StateError('模拟一次读取失败');
    }
    return super.getByDate(date);
  }

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
    DailyFeedback? feedback,
  }) async {
    final gate = nextSaveGate;
    nextSaveGate = null;
    if (gate != null) {
      await gate.future;
    }
    if (saveFailures > 0) {
      saveFailures -= 1;
      throw StateError('模拟一次写入失败');
    }
    return super.save(date: date, content: content, feedback: feedback);
  }
}
