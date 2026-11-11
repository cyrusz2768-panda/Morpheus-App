import 'package:morpheus/features/reminders/data/reminder_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/app/app.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/in_memory_dream_repository.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';

import 'reminder_fakes.dart';

void main() {
  late FakeReminderStore store;
  late FakeReminderNotifications notifications;
  late _DreamRepository dreams;
  late ProviderContainer container;

  setUp(() {
    store = FakeReminderStore();
    notifications = FakeReminderNotifications();
    dreams = _DreamRepository();
    container = ProviderContainer(
      overrides: [
        reminderSettingsStoreProvider.overrideWithValue(store),
        reminderNotificationsProvider.overrideWithValue(notifications),
        dreamRepositoryProvider.overrideWithValue(dreams),
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
  }

  Future<void> openReminders(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-reminders-menu-item')));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('dream-content-field')))
      .controller!
      .text;

  testWidgets('只有第一次进入设置才显示说明，选择稍后不请求系统权限', (tester) async {
    await showApp(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(notifications.requests, 0);
    await openReminders(tester);
    expect(
      find.byKey(const Key('notification-permission-notice')),
      findsOneWidget,
    );
    expect(notifications.requests, 0);
    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
    expect(store.settings.noticeSeen, isTrue);
    expect(notifications.requests, 0);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await openReminders(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('点击说明中的允许通知后才申请，授权后仍由用户开启每日提醒', (tester) async {
    notifications.requestResult = true;
    await showApp(tester);
    await openReminders(tester);
    await tester.tap(find.text('允许通知'));
    await tester.pumpAndSettle();
    expect(notifications.requests, 1);
    expect(find.text('系统通知'), findsNothing);
    expect(store.settings.enabled, isFalse);
    await tester.tap(find.byKey(const Key('daily-reminder-switch')));
    await tester.pumpAndSettle();
    expect(store.settings.enabled, isTrue);
    expect(notifications.scheduled!.timeLabel, '08:00');
  });

  testWidgets('拒绝权限后说明补救入口，返回后仍能记录梦境', (tester) async {
    await showApp(tester);
    await openReminders(tester);
    await tester.tap(find.text('允许通知'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('daily-reminder-switch')));
    await tester.pumpAndSettle();
    expect(store.settings.enabled, isFalse);
    expect(find.byKey(const Key('reminder-time-tile')), findsNothing);
    expect(find.byKey(const Key('reminder-error')), findsOneWidget);
    final systemSettings = find.text('去系统设置');
    await tester.ensureVisible(systemSettings);
    await tester.tap(systemSettings);
    await tester.pumpAndSettle();
    expect(notifications.openedSettings, 1);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '未开启提醒也可以记录的测试内容',
    );
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pumpAndSettle();
    expect(
      (await dreams.getByDate(DateTime.now()))!.content,
      '未开启提醒也可以记录的测试内容',
    );
  });

  testWidgets('打开设置先保存未到防抖时间的草稿', (tester) async {
    await showApp(tester);
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '进入设置前的测试草稿',
    );
    await tester.pump();
    await openReminders(tester);
    expect((await dreams.getByDate(DateTime.now()))!.content, '进入设置前的测试草稿');
    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();
  });

  testWidgets('时间选择器取消不改设置，确认后自动保存', (tester) async {
    store.settings = ReminderSettings(
      enabled: true,
      noticeSeen: true,
      menuHintSeen: true,
    );
    await showApp(tester);
    await openReminders(tester);
    await tester.tap(find.byKey(const Key('reminder-time-tile')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.settings.timeLabel, '08:00');
    await tester.tap(find.byKey(const Key('reminder-time-tile')));
    await tester.pumpAndSettle();
    // 使用真实时间选择器的输入模式，验证中文页面到持久化之间的完整链路。
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '07');
    await tester.enterText(fields.at(1), '35');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(store.settings.timeLabel, '07:35');
    expect(find.text('07:35'), findsOneWidget);
  });

  testWidgets('两个卡片标题在外，关闭时隐藏细项，去掉旧说明和测试入口', (tester) async {
    store.settings = ReminderSettings(noticeSeen: true, menuHintSeen: true);
    await showApp(tester);
    await openReminders(tester);
    expect(find.text('每日提醒'), findsOneWidget);
    expect(find.text('每周回顾'), findsOneWidget);
    expect(find.text('消息通知'), findsNWidgets(2));
    expect(find.byType(Card), findsNWidgets(2));
    for (final title in ['每日提醒', '每周回顾']) {
      expect(
        find.ancestor(of: find.text(title), matching: find.byType(Card)),
        findsNothing,
      );
    }
    expect(find.byKey(const Key('reminder-time-tile')), findsNothing);
    expect(find.byKey(const Key('weekly-reminder-day-tile')), findsNothing);
    expect(find.byKey(const Key('weekly-reminder-time-tile')), findsNothing);
    expect(find.textContaining('给醒来的自己'), findsNothing);
    expect(find.textContaining('设置会自动保存'), findsNothing);
    expect(find.textContaining('提醒可能受系统节电'), findsNothing);
    expect(find.text('系统通知'), findsNothing);
    expect(find.text('去系统设置'), findsNothing);
    expect(find.textContaining('测试通知'), findsNothing);
    expect(find.textContaining('回顾点击时所在'), findsNothing);
  });

  testWidgets('通知点击保存旧日期草稿，并显示当天已有内容', (tester) async {
    final today = DreamEntry.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    await dreams.save(date: today, content: '今天已保存的测试内容');
    await showApp(tester);
    await container
        .read(dreamEditorControllerProvider.notifier)
        .selectDate(yesterday);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '昨天尚未保存的测试草稿',
    );
    notifications.onTap!(ReminderDestination.today);
    await tester.pumpAndSettle();
    expect((await dreams.getByDate(yesterday))!.content, '昨天尚未保存的测试草稿');
    expect(container.read(dreamEditorControllerProvider).date, today);
    expect(text(tester), '今天已保存的测试内容');
  });

  testWidgets('通知从设置页回到当天，关闭时间选择弹窗', (tester) async {
    store.settings = ReminderSettings(
      enabled: true,
      noticeSeen: true,
      menuHintSeen: true,
    );
    await showApp(tester);
    await openReminders(tester);
    await tester.tap(find.byKey(const Key('reminder-time-tile')));
    await tester.pumpAndSettle();
    notifications.onTap!(ReminderDestination.today);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.byKey(const Key('dream-content-field')), findsOneWidget);
  });

  testWidgets('通知触发时保存失败保留原日期和草稿，不覆盖成当天内容', (tester) async {
    await showApp(tester);
    final today = DreamEntry.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    await container
        .read(dreamEditorControllerProvider.notifier)
        .selectDate(yesterday);
    await tester.pumpAndSettle();
    dreams.failSave = true;
    await tester.enterText(
      find.byKey(const Key('dream-content-field')),
      '保存失败也要保留的测试草稿',
    );
    notifications.onTap!(ReminderDestination.today);
    await tester.pumpAndSettle();
    expect(container.read(dreamEditorControllerProvider).date, yesterday);
    expect(text(tester), '保存失败也要保留的测试草稿');
  });

  testWidgets('通知冷启动等待数据库加载后显示当天记录', (tester) async {
    notifications.launchedFromNotification = true;
    await dreams.save(date: DateTime.now(), content: '冷启动读取的测试内容');
    await showApp(tester);
    expect(text(tester), '冷启动读取的测试内容');
    expect(container.read(reminderControllerProvider).tapSequence, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开启回顾只展开该卡片，关闭隐藏细项并保留时间供重开恢复', (tester) async {
    store.settings = ReminderSettings(noticeSeen: true, menuHintSeen: true);
    notifications.granted = true;
    await showApp(tester);
    await openReminders(tester);
    final weekly = find.byKey(const Key('weekly-reminder-switch'));
    await tester.tap(weekly);
    await tester.pumpAndSettle();
    expect(find.text('21:00'), findsOneWidget);
    expect(find.text('星期日'), findsOneWidget);
    expect(store.settings.weeklyEnabled, isTrue);
    expect(store.settings.enabled, isFalse);
    expect(find.byKey(const Key('reminder-time-tile')), findsNothing);
    await tester.tap(weekly);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weekly-reminder-day-tile')), findsNothing);
    expect(notifications.weeklyScheduled, isNull);
    expect(store.settings.weeklyTimeLabel, '21:00');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await openReminders(tester);
    await tester.tap(weekly);
    await tester.pumpAndSettle();
    expect(find.text('21:00'), findsOneWidget);
    expect(notifications.weeklyScheduled!.weeklyWeekday, 7);
  });

  testWidgets('回顾星期选择取消不改设置，星期及时间确认后持久化', (tester) async {
    store.settings = ReminderSettings(
      weeklyEnabled: true,
      noticeSeen: true,
      menuHintSeen: true,
    );
    await showApp(tester);
    await openReminders(tester);
    final day = find.byKey(const Key('weekly-reminder-day-tile'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.settings.weeklyWeekday, 7);
    await tester.tap(day);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weekly-day-3')));
    await tester.pumpAndSettle();
    expect(store.settings.weeklyWeekday, 3);
    final time = find.byKey(const Key('weekly-reminder-time-tile'));
    await tester.ensureVisible(time);
    await tester.tap(time);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '19');
    await tester.enterText(find.byType(TextField).at(1), '45');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(store.settings.weeklyTimeLabel, '19:45');
    expect(store.settings.timeLabel, '08:00');
  });
  testWidgets('关闭保存失败时保持展开和原开关，重试成功后才收起', (tester) async {
    store.settings = ReminderSettings(
      enabled: true,
      hour: 7,
      minute: 35,
      noticeSeen: true,
      menuHintSeen: true,
    );
    notifications.granted = true;
    await showApp(tester);
    await openReminders(tester);
    store.writeFailures = 1;
    final toggle = find.byKey(const Key('daily-reminder-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.settings.enabled, isTrue);
    expect(find.text('07:35'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reminder-time-tile')), findsNothing);
    expect(store.settings.timeLabel, '07:35');
    expect(notifications.scheduled, isNull);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('07:35'), findsOneWidget);
  });

  testWidgets('窄屏大字号两项展开仍可滚动操作且无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    store.settings = ReminderSettings(
      enabled: true,
      weeklyEnabled: true,
      noticeSeen: true,
      menuHintSeen: true,
    );
    await showApp(tester);
    await openReminders(tester);
    final time = find.byKey(const Key('weekly-reminder-time-tile'));
    await tester.ensureVisible(time);
    await tester.pumpAndSettle();
    await tester.tap(time);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}

class _DreamRepository extends InMemoryDreamRepository {
  bool failSave = false;

  @override
  Future<DreamEntry> save({
    required DateTime date,
    required String content,
  }) async {
    if (failSave) throw StateError('Scripted dream save failure');
    return super.save(date: date, content: content);
  }
}
