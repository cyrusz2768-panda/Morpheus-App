import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';

import 'reminder_fakes.dart';

void main() {
  late FakeReminderStore store;
  late FakeReminderNotifications notifications;
  late ProviderContainer container;
  late ReminderController controller;

  setUp(() async {
    store = FakeReminderStore();
    notifications = FakeReminderNotifications();
    container = ProviderContainer(
      overrides: [
        reminderSettingsStoreProvider.overrideWithValue(store),
        reminderNotificationsProvider.overrideWithValue(notifications),
      ],
    );
    controller = container.read(reminderControllerProvider.notifier);
    await controller.load();
  });
  tearDown(() => container.dispose());
  ReminderState current() => container.read(reminderControllerProvider);

  test('启动仅查询权限，默认不开启提醒、不弹系统授权', () {
    expect(current().settings!.enabled, isFalse);
    expect(current().settings!.timeLabel, '08:00');
    expect(notifications.requests, 0);
    expect(notifications.scheduled, isNull);
  });

  test('首次说明选择稍后，记住已读但不请求权限', () async {
    expect(
      await controller.acknowledgeNotice(requestPermission: false),
      isTrue,
    );
    expect(store.settings.noticeSeen, isTrue);
    expect(notifications.requests, 0);
    expect(store.settings.enabled, isFalse);
  });

  test('允许通知只授权，不擅自开启每日提醒', () async {
    notifications.requestResult = true;
    await controller.acknowledgeNotice(requestPermission: true);
    expect(current().permissionGranted, isTrue);
    expect(notifications.requests, 1);
    expect(store.settings.noticeSeen, isTrue);
    expect(store.settings.enabled, isFalse);
  });

  for (final enabled in [false, true]) {
    test('确认菜单教学只保存入口状态，保留${enabled ? '开启' : '关闭'}的提醒与说明', () async {
      store.settings = ReminderSettings(
        enabled: enabled,
        hour: 6,
        minute: 35,
        noticeSeen: enabled,
        menuHintSeen: false,
      );
      notifications.granted = enabled;
      await controller.load();
      final previous = current();
      final schedule = notifications.scheduled;
      final calls = List<String>.of(notifications.calls);
      final permissionChecks = notifications.permissionChecks;

      expect(await controller.acknowledgeMenuHint(), isTrue);

      expect(store.settings.toJson(), {
        ...previous.settings!.toJson(),
        'menuHintSeen': true,
      });
      expect(current().settings, same(store.settings));
      expect(current().permissionGranted, previous.permissionGranted);
      expect(current().tapSequence, previous.tapSequence);
      expect(current().isBusy, isFalse);
      expect(notifications.permissionChecks, permissionChecks);
      expect(notifications.requests, 0);
      expect(notifications.calls, calls);
      expect(notifications.scheduled, same(schedule));
      expect(notifications.testNotifications, 0);
      expect(notifications.openedSettings, 0);
    });
  }

  test('菜单教学保存失败仍保留未读状态与原提醒，可再次确认', () async {
    final original = ReminderSettings(
      enabled: true,
      hour: 21,
      minute: 45,
      noticeSeen: true,
      menuHintSeen: false,
    );
    store.settings = original;
    notifications.granted = true;
    await controller.load();
    final schedule = notifications.scheduled;
    final calls = List<String>.of(notifications.calls);
    final permissionChecks = notifications.permissionChecks;
    store.writeFailures = 1;

    expect(await controller.acknowledgeMenuHint(), isFalse);

    expect(store.settings, same(original));
    expect(current().settings, same(original));
    expect(current().settings!.menuHintSeen, isFalse);
    expect(current().error, isNotNull);
    expect(current().isBusy, isFalse);
    expect(notifications.permissionChecks, permissionChecks);
    expect(notifications.requests, 0);
    expect(notifications.calls, calls);
    expect(notifications.scheduled, same(schedule));

    expect(await controller.acknowledgeMenuHint(), isTrue);
    expect(current().error, isNull);
    expect(store.settings.toJson(), {
      ...original.toJson(),
      'menuHintSeen': true,
    });
    expect(notifications.calls, calls);
  });

  test('菜单教学写入也串行执行，未完成前不允许其他设置覆盖', () async {
    store.settings = ReminderSettings(menuHintSeen: false);
    await controller.load();
    store.writeGate = Completer<void>();
    final first = controller.acknowledgeMenuHint();
    expect(current().isBusy, isTrue);
    expect(current().settings!.menuHintSeen, isFalse);
    expect(await controller.setTime(9, 0), isFalse);
    expect(
      await controller.acknowledgeNotice(requestPermission: true),
      isFalse,
    );

    store.writeGate!.complete();
    expect(await first, isTrue);
    expect(store.settings.menuHintSeen, isTrue);
    expect(store.settings.timeLabel, '08:00');
    expect(store.settings.noticeSeen, isFalse);
    expect(notifications.requests, 0);
  });

  test('拒绝通知不能把每日提醒显示为开启', () async {
    expect(await controller.setEnabled(true), isFalse);
    expect(current().settings!.enabled, isFalse);
    expect(notifications.scheduled, isNull);
    expect(current().error, isNotNull);
  });

  test('改时间再开启，系统日程和磁盘配置使用相同时间', () async {
    await controller.setTime(7, 25);
    notifications.requestResult = true;
    expect(await controller.setEnabled(true), isTrue);
    expect(store.settings.timeLabel, '07:25');
    expect(store.settings.enabled, isTrue);
    expect(notifications.scheduled!.timeLabel, '07:25');
  });

  test('修改已开启的提醒替换日程，关闭后取消', () async {
    notifications.granted = true;
    await controller.setEnabled(true);
    await controller.setTime(9, 10);
    expect(notifications.scheduled!.timeLabel, '09:10');
    await controller.setEnabled(false);
    expect(notifications.scheduled, isNull);
    expect(store.settings.enabled, isFalse);
  });

  test('写入失败时回滚到原时间和原系统调度', () async {
    notifications.granted = true;
    await controller.setEnabled(true);
    store.writeFailures = 1;
    expect(await controller.setTime(9, 10), isFalse);
    expect(store.settings.timeLabel, '08:00');
    expect(current().settings!.timeLabel, '08:00');
    expect(notifications.scheduled!.timeLabel, '08:00');
    expect(current().error, isNotNull);
    expect(await controller.setTime(9, 10), isTrue);
  });

  test('系统调度失败时不把新时间写入磁盘', () async {
    notifications.granted = true;
    await controller.setEnabled(true);
    notifications.scheduleFailures = 1;
    expect(await controller.setTime(6, 30), isFalse);
    expect(store.settings.timeLabel, '08:00');
    expect(notifications.scheduled!.timeLabel, '08:00');
  });

  test('返回前台发现权限撤销时取消日程，恢复权限后按原意愿重排', () async {
    notifications.granted = true;
    await controller.setEnabled(true);
    notifications.granted = false;
    await controller.load();
    expect(current().permissionGranted, isFalse);
    expect(current().settings!.enabled, isTrue);
    expect(notifications.scheduled, isNull);
    expect(notifications.requests, 0);
    notifications.granted = true;
    await controller.load();
    expect(notifications.scheduled!.timeLabel, '08:00');
  });

  test('配置读取失败不覆盖原文件，可重试恢复', () async {
    store.readFailures = 1;
    await controller.load();
    expect(current().error, isNotNull);
    expect(store.settings.timeLabel, '08:00');
    await controller.load();
    expect(current().error, isNull);
  });

  test('写入进行中忽略重复操作，不产生并发覆盖', () async {
    store.writeGate = Completer<void>();
    final first = controller.setTime(7, 0);
    expect(await controller.setTime(9, 0), isFalse);
    store.writeGate!.complete();
    await first;
    expect(store.settings.timeLabel, '07:00');
  });

  test('测试通知要求权限，并且不改变每日开关', () async {
    expect(await controller.showTest(), isFalse);
    expect(notifications.testNotifications, 0);
    notifications.granted = true;
    expect(await controller.showTest(), isTrue);
    expect(notifications.testNotifications, 1);
    expect(store.settings.enabled, isFalse);
  });

  test('冷启动点击只处理一次，后续通知仍可再次触发', () async {
    notifications.launchedFromNotification = true;
    await controller.load();
    expect(current().tapSequence, 1);
    await controller.load();
    expect(current().tapSequence, 1);
    notifications.onTap!();
    expect(current().tapSequence, 2);
  });
}
