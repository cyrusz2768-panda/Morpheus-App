import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/reminders/data/local_reminder_notifications.dart';
import 'package:morpheus/features/reminders/data/reminder_settings_store.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('真实文件写入后，新 Store 实例仍能恢复提醒和已读说明', () async {
    final directory = await Directory.systemTemp.createTemp(
      'morpheus-reminder-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings/reminders.json');
    final first = FileReminderSettingsStore(resolveFile: () async => file);
    expect((await first.read()).noticeSeen, isFalse);
    await first.write(
      ReminderSettings(enabled: true, hour: 7, minute: 15, noticeSeen: true),
    );
    final reopened = FileReminderSettingsStore(resolveFile: () async => file);
    final restored = await reopened.read();
    expect(restored.timeLabel, '07:15');
    expect(restored.enabled, isTrue);
    expect(restored.noticeSeen, isTrue);
    await reopened.write(restored.copyWith(enabled: false, hour: 9));
    expect((await first.read()).enabled, isFalse);
    expect((await first.read()).timeLabel, '09:15');
  });

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
