import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/reminders/data/local_reminder_notifications.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';
import 'package:morpheus/features/reminders/data/reminder_notifications.dart';

import 'package:morpheus/l10n/generated/app_localizations_zh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  final calls = <MethodCall>[];
  var canOpenSettings = true;
  String? launchPayload;
  late LocalReminderNotifications service;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    canOpenSettings = true;
    calls.clear();
    launchPayload = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getNotificationAppLaunchDetails':
          return {
            'notificationLaunchedApp': launchPayload != null,
            'notificationResponse': {
              'payload': launchPayload,
              'notificationResponseType': 0,
            },
          };
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
    await service.initialize((_) {});
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
    await service.initialize((_) {});
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

  test('通知与 Android 渠道从注入资源读取，稳定 ID 和 payload 不变', () async {
    service.dispose();
    service = LocalReminderNotifications(strings: _NotificationResources());
    await service.initialize((_) {});
    await service.scheduleDaily(ReminderSettings(enabled: true));
    await service.showTest();

    final channelArgs =
        calls
                .firstWhere(
                  (call) => call.method == 'createNotificationChannel',
                )
                .arguments
            as Map;
    expect(channelArgs['name'], 'resource channel');
    expect(channelArgs['description'], 'resource description');
    final daily =
        calls.firstWhere((call) => call.method == 'zonedSchedule').arguments
            as Map;
    expect(daily['title'], 'resource daily title');
    expect(daily['body'], 'resource daily body');
    expect(
      (daily['platformSpecifics'] as Map)['channelName'],
      'resource channel',
    );
    final test =
        calls.firstWhere((call) => call.method == 'show').arguments as Map;
    expect(test['title'], 'resource test title');
    expect(test['body'], 'resource test body');
    expect(test['payload'], LocalReminderNotifications.payload);
  });

  test('系统设置无法打开时报告失败，让页面提供重试', () async {
    await service.initialize((_) {});
    canOpenSettings = false;
    await expectLater(service.openSystemSettings(), throwsStateError);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform 周提醒使用独立任务、星期时间重复与通用资源，取消不触碰每日', () async {
      debugDefaultTargetPlatformOverride = platform;
      if (platform == TargetPlatform.iOS) {
        IOSFlutterLocalNotificationsPlugin.registerWith();
      }
      service.dispose();
      service = LocalReminderNotifications(strings: _NotificationResources());
      await service.initialize((_) {});
      await service.scheduleDaily(ReminderSettings(enabled: true));
      await service.scheduleWeekly(
        ReminderSettings(weeklyEnabled: true, weeklyWeekday: 3, weeklyHour: 19),
      );
      await service.scheduleWeekly(ReminderSettings(weeklyEnabled: true));
      final schedules = calls
          .where((c) => c.method == 'zonedSchedule')
          .toList();
      expect(schedules, hasLength(3));
      for (final call in schedules.skip(1)) {
        final args = call.arguments as Map;
        expect(args['id'], LocalReminderNotifications.weeklyId);
        expect(args['payload'], LocalReminderNotifications.weeklyPayload);
        expect(args['title'], 'resource weekly title');
        expect(args['body'], 'resource weekly body');
        expect(args['timeZoneName'], 'Asia/Shanghai');
        expect(
          args['matchDateTimeComponents'],
          DateTimeComponents.dayOfWeekAndTime.index,
        );
        if (platform == TargetPlatform.android) {
          expect(
            (args['platformSpecifics'] as Map)['scheduleMode'],
            'inexactAllowWhileIdle',
          );
        }
      }
      await service.cancelWeekly();
      expect(
        platform == TargetPlatform.iOS
            ? calls.last.arguments
            : (calls.last.arguments as Map)['id'],
        LocalReminderNotifications.weeklyId,
      );
      await service.showTest(weekly: true);
      final args = calls.last.arguments as Map;
      expect(args['id'], LocalReminderNotifications.weeklyTestId);
      expect(args['payload'], LocalReminderNotifications.weeklyPayload);
    });
  }

  test('插件冷启动与热点击识别两项目标，未知payload忽略', () async {
    launchPayload = LocalReminderNotifications.weeklyPayload;
    final taps = <ReminderDestination>[];
    expect(
      await service.initialize(taps.add),
      ReminderDestination.weeklyStatistics,
    );
    Future<void> tap(String payload) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('didReceiveNotificationResponse', {
                'payload': payload,
                'notificationResponseType': 0,
                'id': 1103,
              }),
            ),
            (_) {},
          );
    }

    await tap('unrecognized');
    await tap(LocalReminderNotifications.weeklyPayload);
    await tap(LocalReminderNotifications.payload);
    expect(taps, [
      ReminderDestination.weeklyStatistics,
      ReminderDestination.today,
    ]);
  });
}

// 用不同于正式中文的测试资源验证整条桥接链路，不调用真实系统通知。
class _NotificationResources extends AppLocalizationsZh {
  @override
  String get weeklyNotificationTitle => 'resource weekly title';
  @override
  String get weeklyNotificationBody => 'resource weekly body';
  @override
  String get reminderChannelName => 'resource channel';
  @override
  String get reminderChannelDescription => 'resource description';
  @override
  String get dailyNotificationTitle => 'resource daily title';
  @override
  String get dailyNotificationBody => 'resource daily body';
  @override
  String get testNotificationTitle => 'resource test title';
  @override
  String get testNotificationBody => 'resource test body';
}
