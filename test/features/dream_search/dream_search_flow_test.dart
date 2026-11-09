import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_search/application/dream_search_provider.dart';
import 'package:morpheus/features/dream_search/data/dream_search_repository.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';

import '../reminders/reminder_fakes.dart';

void main() {
  late _EditorRepository editor;
  late _SearchRepository search;
  late FakeReminderNotifications notifications;
  late ProviderContainer container;
  final today = DreamEntry.dateOnly(DateTime.now());
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final field = find.byKey(const Key('dream-search-field'));
  final editorField = find.byKey(const Key('dream-content-field'));
  Finder result(DateTime date) =>
      find.byKey(Key('search-entry-${DreamEntry.dateKey(date)}'));

  setUp(() {
    editor = _EditorRepository();
    search = _SearchRepository(editor);
    notifications = FakeReminderNotifications();
    container = ProviderContainer(
      overrides: [
        dreamRepositoryProvider.overrideWithValue(editor),
        dreamSearchRepositoryProvider.overrideWithValue(search),
        reminderSettingsStoreProvider.overrideWithValue(FakeReminderStore()),
        reminderNotificationsProvider.overrideWithValue(notifications),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> showApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MorpheusApp(),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-search-button')));
    await tester.pumpAndSettle();
  }

  Future<void> query(WidgetTester tester, String term) async {
    await tester.enterText(field, term);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  String editorContent(WidgetTester tester) =>
      tester.widget<TextField>(editorField).controller!.text;

  testWidgets('🔍进入后自动聚焦，导航前保存新草稿；结果选日读取完整原文', (tester) async {
    const original = '  海边的旧梦\n🌙 原格式  ';
    await editor.save(date: yesterday, content: original);
    await showApp(tester);
    await tester.enterText(editorField, '今天的海边新草稿');
    await tester.tap(find.byKey(const Key('open-search-button')));
    await tester.pump();
    await tester.pump();
    expect((await editor.getByDate(today))!.content, '今天的海边新草稿');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(search.calls, isEmpty);
    await query(tester, '海边');
    expect(result(today), findsOneWidget);
    expect(result(yesterday), findsOneWidget);
    expect(
      tester.getTopLeft(result(today)).dy,
      lessThan(tester.getTopLeft(result(yesterday)).dy),
    );
    await tester.tap(result(yesterday));
    await tester.pumpAndSettle();
    expect(editorContent(tester), original);
    expect(container.read(dreamEditorControllerProvider).date, yesterday);
    await tester.tap(find.byKey(const Key('back-to-today-button')));
    await tester.pumpAndSettle();
    expect(editorContent(tester), '今天的海边新草稿');
  });

  testWidgets('防抖仅查询最终词，空白不查询，清空后不保留旧结果且恢复焦点', (tester) async {
    await editor.save(date: yesterday, content: '月亮');
    await showApp(tester);
    await openSearch(tester);
    await tester.enterText(field, '月');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await query(tester, '月亮');
    expect(search.calls, ['月亮']);
    expect(result(yesterday), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear-dream-search')));
    await tester.pumpAndSettle();
    expect(result(yesterday), findsNothing);
    expect(find.text('输入关键词，搜索梦境正文'), findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await query(tester, ' \n\t');
    expect(search.calls, ['月亮']);
  });

  testWidgets('组词期间不查拼音，只有 composing 结束也会查询确认的文字', (tester) async {
    await editor.save(date: yesterday, content: '海边');
    await showApp(tester);
    await openSearch(tester);
    final controller = tester.widget<TextField>(field).controller!;
    controller.value = const TextEditingValue(
      text: '海边',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(search.calls, isEmpty);
    expect(find.text('完成输入后开始搜索'), findsOneWidget);
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(search.calls, ['海边']);
    expect(result(yesterday), findsOneWidget);
  });

  testWidgets('旧词慢查询不会覆盖新词；清空后晚到结果不复活', (tester) async {
    final old = await editor.save(date: yesterday, content: '旧词');
    final fresh = await editor.save(date: today, content: '新词');
    final oldGate = Completer<List<DreamEntry>>();
    final newGate = Completer<List<DreamEntry>>();
    search.gates.addAll({'旧词': oldGate, '新词': newGate});
    await showApp(tester);
    await openSearch(tester);
    await query(tester, '旧词');
    await query(tester, '新词');
    newGate.complete([fresh]);
    await tester.pumpAndSettle();
    expect(result(today), findsOneWidget);
    oldGate.complete([old]);
    await tester.pumpAndSettle();
    expect(result(yesterday), findsNothing);
    expect(result(today), findsOneWidget);
    final lateGate = Completer<List<DreamEntry>>();
    search.gates['晚到'] = lateGate;
    await query(tester, '晚到');
    await tester.tap(find.byKey(const Key('clear-dream-search')));
    await tester.pumpAndSettle();
    lateGate.complete([old]);
    await tester.pumpAndSettle();
    expect(result(yesterday), findsNothing);
    expect(find.text('输入关键词，搜索梦境正文'), findsOneWidget);
  });

  testWidgets('搜索失败保留关键词供重试，无匹配与失败分别提示', (tester) async {
    await editor.save(date: yesterday, content: '月亮');
    search.failures = 1;
    await showApp(tester);
    await openSearch(tester);
    await query(tester, '月亮');
    expect(find.text('搜索失败，请重试。'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '月亮');
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(result(yesterday), findsOneWidget);
    await query(tester, '不存在');
    expect(find.text('没有找到匹配的梦境'), findsOneWidget);
    expect(find.text('搜索失败，请重试。'), findsNothing);
  });

  testWidgets('入口 await 间隙的末尾输入也保存，快速连点仅打开一个搜索页', (tester) async {
    await showApp(tester);
    final input = tester.widget<TextField>(editorField);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('open-search-button')),
    );
    button.onPressed!();
    button.onPressed!();
    input.onChanged!('输入法交付的末尾草稿');
    await tester.pumpAndSettle();
    expect((await editor.getByDate(today))!.content, '输入法交付的末尾草稿');
    expect(field, findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(editorField, findsOneWidget);
    await openSearch(tester);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
  });

  testWidgets('保存失败不进入搜索且保留草稿，重试后可搜索，清空后不再命中', (tester) async {
    await showApp(tester);
    editor.saveFailures = 1;
    await tester.enterText(editorField, '保留的月亮草稿');
    await openSearch(tester);
    expect(field, findsNothing);
    expect(editorContent(tester), '保留的月亮草稿');
    expect(search.calls, isEmpty);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await openSearch(tester);
    await query(tester, '月亮');
    expect(result(today), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.enterText(editorField, ' \n\t');
    await openSearch(tester);
    await query(tester, '月亮');
    expect(result(today), findsNothing);
    expect(await editor.getByDate(today), isNull);
  });

  testWidgets('搜索页打开期间点击提醒通知，关闭搜索并安全回到当天', (tester) async {
    await editor.save(date: today, content: '今天的月亮');
    await editor.save(date: yesterday, content: '昨天的海边');
    await showApp(tester);
    await container
        .read(dreamEditorControllerProvider.notifier)
        .selectDate(yesterday);
    await tester.pumpAndSettle();
    await openSearch(tester);
    notifications.onTap!();
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(container.read(dreamEditorControllerProvider).date, today);
    expect(editorContent(tester), '今天的月亮');
    expect((await editor.getByDate(yesterday))!.content, '昨天的海边');
  });
}

/// 搜索测试通过接口注入查询延迟和故障；不读开发者的真实 SQLite 文件。
class _SearchRepository implements IDreamSearchRepository {
  _SearchRepository(this.editor);
  final InMemoryDreamRepository editor;
  final calls = <String>[];
  final gates = <String, Completer<List<DreamEntry>>>{};
  int failures = 0;

  @override
  Future<List<DreamEntry>> search(String keyword) async {
    calls.add(keyword);
    if (failures > 0) {
      failures--;
      throw StateError('测试用搜索失败');
    }
    if (gates[keyword] case final gate?) return gate.future;
    return (await editor.getAll())
        .where(
          (entry) =>
              entry.content.toLowerCase().contains(keyword.toLowerCase()),
        )
        .toList();
  }
}

class _EditorRepository extends InMemoryDreamRepository {
  int saveFailures = 0;

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
  }) async {
    if (saveFailures > 0) {
      saveFailures--;
      throw StateError('测试用保存失败');
    }
    return super.save(date: date, content: content);
  }
}
