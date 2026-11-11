import 'dart:async';

import 'package:morpheus/features/reminders/data/reminder_notifications.dart';
import 'package:morpheus/features/reminders/data/reminder_settings_store.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';

/// 这些替身只在测试中使用，记录系统调用和故障，不触碰真实通知权限。
class FakeReminderStore implements IReminderSettingsStore {
  FakeReminderStore([ReminderSettings? initial])
    : settings = initial ?? ReminderSettings(menuHintSeen: true);
  ReminderSettings settings;
  int writeFailures = 0;
  int readFailures = 0;
  Completer<void>? writeGate;

  @override
  Future<ReminderSettings> read() async {
    if (readFailures > 0) {
      readFailures--;
      throw StateError('Scripted read failure');
    }
    return settings;
  }

  @override
  Future<void> write(ReminderSettings next) async {
    await writeGate?.future;
    if (writeFailures > 0) {
      writeFailures--;
      throw StateError('Scripted write failure');
    }
    settings = next;
  }
}

class FakeReminderNotifications implements IReminderNotifications {
  bool granted = false;
  bool requestResult = false;
  bool launchedFromNotification = false;
  ReminderDestination launchDestination = ReminderDestination.today;
  ReminderSettings? weeklyScheduled;
  int weeklyScheduleFailures = 0;
  int weeklyTestNotifications = 0;
  int requests = 0;
  int permissionChecks = 0;
  int testNotifications = 0;
  int openedSettings = 0;
  int scheduleFailures = 0;
  ReminderSettings? scheduled;
  void Function(ReminderDestination)? onTap;
  final calls = <String>[];

  @override
  Future<ReminderDestination?> initialize(
    void Function(ReminderDestination) callback,
  ) async {
    onTap = callback;
    return launchedFromNotification ? launchDestination : null;
  }

  @override
  Future<bool> isPermissionGranted() async {
    permissionChecks++;
    return granted;
  }

  @override
  Future<bool> requestPermission() async {
    requests++;
    granted = requestResult;
    return granted;
  }

  @override
  Future<void> scheduleDaily(ReminderSettings settings) async {
    calls.add('schedule:${settings.timeLabel}');
    if (scheduleFailures > 0) {
      scheduleFailures--;
      throw StateError('Scripted scheduling failure');
    }
    scheduled = settings;
  }

  @override
  Future<void> cancelDaily() async {
    calls.add('cancel');
    scheduled = null;
  }

  @override
  Future<void> openSystemSettings() async => openedSettings++;

  @override
  Future<void> scheduleWeekly(ReminderSettings settings) async {
    if (weeklyScheduleFailures > 0) {
      weeklyScheduleFailures--;
      throw StateError('Scripted weekly scheduling failure');
    }
    weeklyScheduled = settings;
  }

  @override
  Future<void> cancelWeekly() async => weeklyScheduled = null;

  @override
  Future<void> showTest({bool weekly = false}) async {
    if (weekly) {
      weeklyTestNotifications++;
    } else {
      testNotifications++;
    }
  }

  @override
  void dispose() => onTap = null;
}
