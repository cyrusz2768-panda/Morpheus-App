import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/reminders/data/local_reminder_notifications.dart';
import 'package:morpheus/features/reminders/data/reminder_settings_store.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('真实文件写入后，新 Store 实例仍能恢复提醒、已读说明与菜单教学', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus-reminder-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings/reminders.json');
    final first = FileReminderSettingsStore(resolveFile: () async => file);
    expect((await first.read()).noticeSeen, isFalse);
    expect((await first.read()).menuHintSeen, isFalse);
    await first.write(
      ReminderSettings(
        enabled: true,
        hour: 7,
        minute: 15,
        noticeSeen: true,
        menuHintSeen: true,
      ),
    );
    final reopened = FileReminderSettingsStore(resolveFile: () async => file);
    final restored = await reopened.read();
    expect(restored.timeLabel, '07:15');
    expect(restored.enabled, isTrue);
    expect(restored.noticeSeen, isTrue);
    expect(restored.menuHintSeen, isTrue);
    await reopened.write(restored.copyWith(enabled: false, hour: 9));
    expect((await first.read()).enabled, isFalse);
    expect((await first.read()).timeLabel, '09:15');
    expect((await first.read()).menuHintSeen, isTrue);
  });

  test('旧配置缺少菜单教学字段时保留已有设置，确认后持久化新字段', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus-reminder-migration-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/reminders.json');
    final legacy = {
      'enabled': true,
      'hour': 22,
      'minute': 40,
      'noticeSeen': true,
    };
    final original = jsonEncode({'notifications': legacy});
    await file.writeAsString(original);
    final store = FileReminderSettingsStore(resolveFile: () async => file);

    final migrated = await store.read();

    expect(migrated.toJson(), {...legacy, 'menuHintSeen': false});
    // 读取旧版只补内存默认值，不因一次升级擅自重写已有配置文件。
    expect(await file.readAsString(), original);
    await store.write(migrated.copyWith(menuHintSeen: true));
    final reopened = FileReminderSettingsStore(resolveFile: () async => file);
    expect((await reopened.read()).toJson(), {...legacy, 'menuHintSeen': true});
  });

  test('菜单教学写入临时文件失败时，原文件与未读状态仍可恢复', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus-reminder-write-failure-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/reminders.json');
    final store = FileReminderSettingsStore(resolveFile: () async => file);
    final original = ReminderSettings(
      enabled: true,
      hour: 20,
      minute: 25,
      noticeSeen: true,
      menuHintSeen: false,
    );
    await store.write(original);
    final originalContents = await file.readAsString();
    // 只阻挡原子保存使用的临时路径，验证失败不会截断真实配置。
    final blockedTemporary = await Directory('${file.path}.tmp').create();

    await expectLater(
      store.write(original.copyWith(menuHintSeen: true)),
      throwsA(isA<FileSystemException>()),
    );

    expect(await file.readAsString(), originalContents);
    final reopened = FileReminderSettingsStore(resolveFile: () async => file);
    expect((await reopened.read()).toJson(), original.toJson());
    await blockedTemporary.delete();
    await reopened.write(original.copyWith(menuHintSeen: true));
    expect((await store.read()).menuHintSeen, isTrue);
  });

  for (final invalid in [null, 0, 'true']) {
    test('菜单教学字段存在但类型为 $invalid 时报告错误并保留原文件', () async {
      final directory = await Directory.systemTemp.createTemp(
        'morpheus-reminder-invalid-menu-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/reminders.json');
      final original = jsonEncode({
        'notifications': {
          'enabled': true,
          'hour': 7,
          'minute': 15,
          'noticeSeen': true,
          'menuHintSeen': invalid,
        },
      });
      await file.writeAsString(original);
      final store = FileReminderSettingsStore(resolveFile: () async => file);

      await expectLater(store.read(), throwsFormatException);

      expect(await file.readAsString(), original);
    });
  }

  test('损坏的配置报告错误，不静默覆盖原始文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus-reminder-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/reminders.json');
    await file.writeAsString('{"notifications":');
    final store = FileReminderSettingsStore(resolveFile: () async => file);
    await expectLater(store.read(), throwsFormatException);
    expect(await file.readAsString(), '{"notifications":');
  });

  test('非法时间不能成为有效配置', () {
    expect(() => ReminderSettings(hour: 24), throwsRangeError);
    expect(() => ReminderSettings(minute: -1), throwsRangeError);
    expect(
      () => ReminderSettings.fromJson({'enabled': 'true'}),
      throwsFormatException,
    );
  });

  test('当天时间未到用今天，已到则安排明天', () {
    final shanghai = tz.getLocation('Asia/Shanghai');
    final before = tz.TZDateTime(shanghai, 2026, 11, 6, 7, 59);
    expect(
      nextReminderTime(before, 8, 0),
      tz.TZDateTime(shanghai, 2026, 11, 6, 8),
    );
    final at = tz.TZDateTime(shanghai, 2026, 11, 6, 8);
    expect(nextReminderTime(at, 8, 0), tz.TZDateTime(shanghai, 2026, 11, 7, 8));
  });

  test('跨月底、跨年仍安排下一个本地日历日', () {
    final zone = tz.getLocation('Asia/Shanghai');
    final now = tz.TZDateTime(zone, 2026, 12, 31, 23);
    expect(nextReminderTime(now, 8, 0), tz.TZDateTime(zone, 2027, 1, 1, 8));
  });

  test('夏令时开始时仍是次日八点，而非固定二十四小时后', () {
    final zone = tz.getLocation('America/New_York');
    final now = tz.TZDateTime(zone, 2026, 3, 7, 8);
    final next = nextReminderTime(now, 8, 0);
    expect(next.hour, 8);
    expect(next.difference(now), const Duration(hours: 23));
  });

  test('夏令时结束时仍是次日八点', () {
    final zone = tz.getLocation('America/New_York');
    final now = tz.TZDateTime(zone, 2026, 10, 31, 8);
    expect(
      nextReminderTime(now, 8, 0).difference(now),
      const Duration(hours: 25),
    );
  });
}
