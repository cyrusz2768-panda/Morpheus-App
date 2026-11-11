import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/reminders/data/local_reminder_notifications.dart';
import 'package:morpheus/features/reminders/data/reminder_settings_store.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const weeklyDefaults = {
  'weeklyEnabled': false,
  'weeklyWeekday': 7,
  'weeklyHour': 21,
  'weeklyMinute': 0,
};

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

    expect(migrated.toJson(), {
      ...legacy,
      'menuHintSeen': false,
      ...weeklyDefaults,
    });
    // 读取旧版只补内存默认值，不因一次升级擅自重写已有配置文件。
    expect(await file.readAsString(), original);
    await store.write(migrated.copyWith(menuHintSeen: true));
    final reopened = FileReminderSettingsStore(resolveFile: () async => file);
    expect((await reopened.read()).toJson(), {
      ...legacy,
      'menuHintSeen': true,
      ...weeklyDefaults,
    });
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

  test('回顾设置在真实文件重开后保留，关闭不会改每日提醒', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus-weekly-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/reminders.json');
    final store = FileReminderSettingsStore(resolveFile: () async => file);
    await store.write(
      ReminderSettings(
        enabled: true,
        hour: 6,
        weeklyEnabled: true,
        weeklyWeekday: 3,
        weeklyHour: 20,
        weeklyMinute: 45,
      ),
    );
    final reopened = FileReminderSettingsStore(resolveFile: () async => file);
    final settings = await reopened.read();
    expect(settings.weeklyEnabled, isTrue);
    expect(settings.weeklyWeekday, 3);
    expect(settings.weeklyTimeLabel, '20:45');
    await reopened.write(settings.copyWith(weeklyEnabled: false));
    expect((await store.read()).weeklyEnabled, isFalse);
    expect((await store.read()).enabled, isTrue);
    expect((await store.read()).hour, 6);
  });

  test('回顾字段缺失兼容旧配置，显式损坏或越界拒绝', () {
    final legacy = {
      'enabled': true,
      'hour': 6,
      'minute': 15,
      'noticeSeen': true,
    };
    final migrated = ReminderSettings.fromJson(legacy);
    expect(migrated.weeklyEnabled, isFalse);
    expect(migrated.weeklyWeekday, 7);
    expect(migrated.weeklyTimeLabel, '21:00');
    expect(migrated.timeLabel, '06:15');
    for (final field in weeklyDefaults.keys) {
      for (final bad in [null, 'invalid']) {
        expect(
          () => ReminderSettings.fromJson({...legacy, field: bad}),
          throwsFormatException,
        );
      }
    }
    for (final bad in [
      {'weeklyWeekday': 0},
      {'weeklyWeekday': 8},
      {'weeklyHour': 24},
      {'weeklyMinute': 60},
    ]) {
      expect(
        () => ReminderSettings.fromJson({...legacy, ...bad}),
        throwsRangeError,
      );
    }
  });

  test('周提醒当天未到、刚好已到、跨年按本地日历星期计算', () {
    final zone = tz.getLocation('Asia/Shanghai');
    expect(
      nextWeeklyReminderTime(tz.TZDateTime(zone, 2026, 11, 8, 20), 7, 21, 0),
      tz.TZDateTime(zone, 2026, 11, 8, 21),
    );
    expect(
      nextWeeklyReminderTime(tz.TZDateTime(zone, 2026, 11, 8, 21), 7, 21, 0),
      tz.TZDateTime(zone, 2026, 11, 15, 21),
    );
    expect(
      nextWeeklyReminderTime(tz.TZDateTime(zone, 2026, 12, 31, 23), 7, 21, 0),
      tz.TZDateTime(zone, 2027, 1, 3, 21),
    );
  });

  test('周提醒跳过不存在的本地时间，重复模板仍保留原时分', () {
    final zone = tz.getLocation('America/New_York');
    final next = nextWeeklyReminderTime(
      tz.TZDateTime(zone, 2026, 3, 7, 12),
      7,
      2,
      30,
    );
    expect(next, tz.TZDateTime(zone, 2026, 3, 15, 2, 30));
  });

  test('周提醒跨夏令时仍保持同一星期和时间', () {
    final zone = tz.getLocation('America/New_York');
    final spring = tz.TZDateTime(zone, 2026, 3, 1, 21);
    final autumn = tz.TZDateTime(zone, 2026, 10, 25, 21);
    final nextSpring = nextWeeklyReminderTime(spring, 7, 21, 0);
    final nextAutumn = nextWeeklyReminderTime(autumn, 7, 21, 0);
    expect(nextSpring.weekday, 7);
    expect(nextSpring.hour, 21);
    expect(nextSpring.difference(spring).inHours, 167);
    expect(nextAutumn.hour, 21);
    expect(nextAutumn.difference(autumn).inHours, 169);
  });
}
