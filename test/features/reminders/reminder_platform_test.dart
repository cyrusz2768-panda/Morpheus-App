import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/reminders/data/local_reminder_notifications.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  final calls = <MethodCall>[];
  var canOpenSettings = true;
  late LocalReminderNotifications service;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    canOpenSettings = true;
    calls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'getNotificationChannels':
          return <Object>[];
        case 'checkPermissions':
          return {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isSoundEnabled': true,
          };
        case 'openAppNotificationSettings':
          return canOpenSettings;
        default:
          return true;
      }
    });
    messenger.setMockMethodCallHandler(
      timezoneChannel,
      (_) async => 'Asia/Shanghai',
    );
    service = LocalReminderNotifications();
  });

  tearDown(() {
    service.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android 真实插件桥接每天同一个 ID，使用当地时区并替换旧时间', () async {
    await service.initialize(() {});
    expect(
      calls.where((c) => c.method == 'requestNotificationsPermission'),
      isEmpty,
    );
    await service.scheduleDaily(ReminderSettings(enabled: true, hour: 8));
    await service.scheduleDaily(ReminderSettings(enabled: true, hour: 9));
    final schedules = calls.where((c) => c.method == 'zonedSchedule').toList();
    expect(schedules, hasLength(2));
    for (final call in schedules) {
      final args = call.arguments as Map;
      expect(args['id'], LocalReminderNotifications.dailyId);
      expect(args['payload'], LocalReminderNotifications.payload);
      expect(args['timeZoneName'], 'Asia/Shanghai');
      expect(args['matchDateTimeComponents'], DateTimeComponents.time.index);
      expect(
        (args['platformSpecifics'] as Map)['scheduleMode'],
        'inexactAllowWhileIdle',
      );
    }
    await service.cancelDaily();
    expect(
      (calls.last.arguments as Map)['id'],
      LocalReminderNotifications.dailyId,
    );
  });

  test('iOS 初始化不请求通知，明确调用申请时才请求 alert 和 sound', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    await service.initialize(() {});
    final init =
        calls.firstWhere((c) => c.method == 'initialize').arguments as Map;
    expect(init['requestAlertPermission'], isFalse);
    expect(init['requestSoundPermission'], isFalse);
    expect(init['requestBadgePermission'], isFalse);
    expect(calls.where((c) => c.method == 'requestPermissions'), isEmpty);
    expect(await service.requestPermission(), isTrue);
    final request =
        calls.firstWhere((c) => c.method == 'requestPermissions').arguments
            as Map;
    expect(request['alert'], isTrue);
    expect(request['sound'], isTrue);
    expect(request['badge'], isFalse);
  });

  test('系统设置无法打开时报告失败，让页面提供重试', () async {
    await service.initialize(() {});
    canOpenSettings = false;
    await expectLater(service.openSystemSettings(), throwsStateError);
  });
}
