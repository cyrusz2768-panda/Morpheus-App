import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';
import 'package:morpheus/features/reminders/presentation/reminder_settings_page.dart';

import '../../reminders/reminder_fakes.dart';

void main() {
  late _MenuStore store;
  late FakeReminderNotifications notifications;
  late _DreamRepository dreams;
  late ProviderContainer container;

  ProviderContainer createContainer() => ProviderContainer(
    overrides: [
      reminderSettingsStoreProvider.overrideWithValue(store),
      reminderNotificationsProvider.overrideWithValue(notifications),
      dreamRepositoryProvider.overrideWithValue(dreams),
    ],
  );

  setUp(() {
    // 全部依赖都留在内存中，首次提示不能读到开发者的提醒设置或申请真机权限。
    store = _MenuStore();
    notifications = FakeReminderNotifications();
    dreams = _DreamRepository();
    container = createContainer();
  });
  tearDown(() => container.dispose());

  Future<void> showApp(WidgetTester tester, {bool settle = true}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MorpheusApp(),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-menu-button')));
    await tester.pumpAndSettle();
  }

  Future<void> chooseReminders(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-reminders-menu-item')));
    await tester.pumpAndSettle();
  }

  bool isDrawerOpen(WidgetTester tester) => tester
      .state<ScaffoldState>(
        find.ancestor(
          of: find.byKey(const Key('open-menu-button')),
          matching: find.byType(Scaffold),
        ),
      )
      .isDrawerOpen;

  testWidgets('首页左上角菜单打开大部分屏宽的抽屉，通知设置返回后抽屉保持关闭', (tester) async {
    store.settings = ReminderSettings(noticeSeen: true, menuHintSeen: true);
    await showApp(tester);

    final menuButton = find.byKey(const Key('open-menu-button'));
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.leading?.key, const Key('open-menu-button'));
    expect(
      find.descendant(of: menuButton, matching: find.byIcon(Icons.menu)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('open-reminders-button')), findsNothing);
    expect(find.byKey(const Key('menu-reminder-intro')), findsNothing);

    await openMenu(tester);
    final drawer = find.byKey(const Key('main-menu-drawer'));
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(isDrawerOpen(tester), isTrue);
    expect(tester.getSize(drawer).width, closeTo(screenWidth * 0.82, 0.1));
    final entry = find.byKey(const Key('open-reminders-menu-item'));
    expect(tester.widget<ListTile>(entry).title, isA<Text>());
    expect(
      find.descendant(of: entry, matching: find.text('通知设置')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: entry,
        matching: find.byIcon(Icons.notifications_outlined),
      ),
      findsOneWidget,
    );

    await chooseReminders(tester);
    // push() 保留原 URI；直接检查当前可见的设置页和可操作控件。
    expect(find.byType(ReminderSettingsPage), findsOneWidget);
    expect(find.byKey(const Key('daily-reminder-switch')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderSettingsPage), findsNothing);
    expect(isDrawerOpen(tester), isFalse);
    expect(find.byKey(const Key('dream-content-field')), findsOneWidget);
  });

  testWidgets('首次入口说明包含真实菜单图标，关闭时只记住菜单说明而不申请权限', (tester) async {
    store.settings = ReminderSettings(hour: 7, minute: 35);
    await showApp(tester);

    final intro = find.byKey(const Key('menu-reminder-intro'));
    expect(intro, findsOneWidget);
    expect(find.text('设置每日梦境提醒'), findsOneWidget);
    final content = tester.widget<AlertDialog>(intro).content! as Text;
    final span = content.textSpan! as TextSpan;
    // 图标必须位于正文的 WidgetSpan 中；按钮上的图标不能代替入口说明。
    final inlineIcons = span.children!
        .whereType<WidgetSpan>()
        .map((span) => span.child)
        .whereType<Icon>();
    expect(inlineIcons.map((icon) => icon.icon), contains(Icons.menu));
    expect(span.toPlainText(), contains('左上角'));
    expect(span.toPlainText(), contains('发送时间'));
    expect(notifications.requests, 0);
    expect(
      find.byKey(const Key('notification-permission-notice')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('dismiss-menu-intro-button')));
    await tester.pumpAndSettle();
    expect(intro, findsNothing);
    expect(isDrawerOpen(tester), isFalse);
    expect(store.settings.menuHintSeen, isTrue);
    expect(store.settings.noticeSeen, isFalse);
    expect(store.settings.enabled, isFalse);
    expect(store.settings.timeLabel, '07:35');
    expect(notifications.requests, 0);
  });

  testWidgets('关闭首次说明后重新创建整个应用仍不再显示', (tester) async {
    store.settings = ReminderSettings();
    await showApp(tester);
    await tester.tap(find.byKey(const Key('dismiss-menu-intro-button')));
    await tester.pumpAndSettle();
    expect(store.settings.menuHintSeen, isTrue);

    // 重新创建 Router、页面和 ProviderContainer，验证持久化标志而非页面局部变量。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
    container = createContainer();
    await showApp(tester);
    expect(find.byKey(const Key('menu-reminder-intro')), findsNothing);
    expect(find.byKey(const Key('dream-content-field')), findsOneWidget);
    expect(notifications.requests, 0);
  });

  testWidgets('首次说明的打开菜单只展开抽屉，设置页仍单独解释并征求通知权限', (tester) async {
    store.settings = ReminderSettings();
    notifications.requestResult = true;
    await showApp(tester);
    await tester.tap(find.byKey(const Key('intro-open-menu-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('menu-reminder-intro')), findsNothing);
    expect(isDrawerOpen(tester), isTrue);
    expect(find.byType(ReminderSettingsPage), findsNothing);
    expect(find.byKey(const Key('dream-content-field')), findsOneWidget);
    expect(store.settings.menuHintSeen, isTrue);
    expect(store.settings.noticeSeen, isFalse);
    expect(notifications.requests, 0);

    await chooseReminders(tester);
    expect(find.byType(ReminderSettingsPage), findsOneWidget);
    expect(
      find.byKey(const Key('notification-permission-notice')),
      findsOneWidget,
    );
    expect(notifications.requests, 0);
    await tester.tap(find.text('允许通知'));
    await tester.pumpAndSettle();
    expect(notifications.requests, 1);
    expect(store.settings.noticeSeen, isTrue);
    expect(store.settings.menuHintSeen, isTrue);
    expect(store.settings.enabled, isFalse);
  });

  testWidgets('首次说明写入失败仍只显示一次，不在重建或设置返回时反复打断', (tester) async {
    store.settings = ReminderSettings(noticeSeen: true);
    store.writeFailures = 1;
    await showApp(tester);
    await tester.tap(find.byKey(const Key('dismiss-menu-intro-button')));
    await tester.pumpAndSettle();
    expect(store.settings.menuHintSeen, isFalse);

    await container.read(reminderControllerProvider.notifier).load();
    await tester.pumpAndSettle();
    await openMenu(tester);
    await chooseReminders(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '关闭说明后仍然可以记录梦境',
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-reminder-intro')), findsNothing);
    expect(store.settings.menuHintSeen, isFalse);
    expect(notifications.requests, 0);
  });

  testWidgets('菜单进入设置遇到草稿保存失败时留在编辑器，重试后才允许进入', (tester) async {
    store.settings = ReminderSettings(noticeSeen: true, menuHintSeen: true);
    await showApp(tester);
    dreams.failSave = true;
    const draft = '打开通知设置时不能丢失的草稿';
    await tester.enterText(find.byKey(const Key('dream-content-field')), draft);
    await tester.pump();
    await openMenu(tester);
    await chooseReminders(tester);

    expect(find.byType(ReminderSettingsPage), findsNothing);
    expect(isDrawerOpen(tester), isFalse);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('dream-content-field')))
          .controller!
          .text,
      draft,
    );
    expect(await dreams.getByDate(DateTime.now()), isNull);
    expect(find.text('重试'), findsOneWidget);
    expect(notifications.requests, 0);

    dreams.failSave = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await openMenu(tester);
    await chooseReminders(tester);
    expect(find.byType(ReminderSettingsPage), findsOneWidget);
    expect(find.byKey(const Key('daily-reminder-switch')), findsOneWidget);
    expect((await dreams.getByDate(DateTime.now()))!.content, draft);
  });

  testWidgets('首次说明等待编辑器和提醒设置均完成加载', (tester) async {
    store.settings = ReminderSettings();
    final editorRead = Completer<void>();
    final reminderRead = Completer<void>();
    dreams.readGate = editorRead;
    store.readGate = reminderRead;
    await showApp(tester, settle: false);
    await tester.pump();
    expect(find.byKey(const Key('menu-reminder-intro')), findsNothing);

    reminderRead.complete();
    await tester.pump();
    await tester.pump();
    expect(container.read(reminderControllerProvider).isLoading, isFalse);
    expect(container.read(dreamEditorControllerProvider).isLoading, isTrue);
    expect(find.byKey(const Key('menu-reminder-intro')), findsNothing);

    editorRead.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-reminder-intro')), findsOneWidget);
    expect(notifications.requests, 0);
    await tester.tap(find.byKey(const Key('dismiss-menu-intro-button')));
    await tester.pumpAndSettle();
  });

  testWidgets('设置在抽屉打开期间读完时，首次说明等待抽屉关闭', (tester) async {
    store.settings = ReminderSettings();
    final reminderRead = Completer<void>();
    store.readGate = reminderRead;
    await showApp(tester, settle: false);
    await tester.pump();
    await tester.pump();
    expect(container.read(dreamEditorControllerProvider).isLoading, isFalse);
    await openMenu(tester);
    expect(isDrawerOpen(tester), isTrue);

    reminderRead.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-reminder-intro')), findsNothing);
    expect(notifications.requests, 0);
    await tester.tap(find.byTooltip('关闭菜单'));
    await tester.pumpAndSettle();
    expect(isDrawerOpen(tester), isFalse);
    expect(find.byKey(const Key('menu-reminder-intro')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dismiss-menu-intro-button')));
    await tester.pumpAndSettle();
  });
}

class _MenuStore extends FakeReminderStore {
  Completer<void>? readGate;

  @override
  Future<ReminderSettings> read() async {
    await readGate?.future;
    return super.read();
  }
}

class _DreamRepository extends InMemoryDreamRepository {
  Completer<void>? readGate;
  bool failSave = false;

  @override
  Future<DreamEntry?> getByDate(DateTime date) async {
    await readGate?.future;
    return super.getByDate(date);
  }

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
  }) async {
    if (failSave) throw StateError('Scripted dream save failure');
    return super.save(date: date, content: content);
  }
}
