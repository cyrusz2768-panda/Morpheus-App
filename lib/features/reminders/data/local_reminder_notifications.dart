import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:morpheus/features/reminders/data/reminder_notifications.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';
import 'package:morpheus/l10n/app_text.dart';

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 以“当地日历中的下一天”计算时间，不能直接加固定的 24 小时。
/// 夏令时切换时，一天可能只有 23 小时或长达 25 小时。
tz.TZDateTime nextReminderTime(tz.TZDateTime now, int hour, int minute) {
  RangeError.checkValueInInterval(hour, 0, 23, 'hour');
  RangeError.checkValueInInterval(minute, 0, 59, 'minute');
  final candidate = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );
  return candidate.isAfter(now)
      ? candidate
      : tz.TZDateTime(
          now.location,
          now.year,
          now.month,
          now.day + 1,
          hour,
          minute,
        );
}

class LocalReminderNotifications implements IReminderNotifications {
  LocalReminderNotifications({
    FlutterLocalNotificationsPlugin? plugin,
    AppLocalizations? strings,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _strings = strings ?? lookupAppLocalizations(morpheusLocale);

  // 平台服务没有 BuildContext；使用应用注入的资源，通知不复制另一套文案。
  final AppLocalizations _strings;

  static const dailyId = 1101;
  static const testId = 1102;
  static const channelId = 'dream_reminders';
  static const payload = 'morpheus:today';

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _initialization;
  void Function()? _onTap;

  NotificationDetails get _details => NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      _strings.reminderChannelName,
      channelDescription: _strings.reminderChannelDescription,
      icon: 'ic_stat_moon',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      presentBadge: false,
    ),
  );

  @override
  Future<bool> initialize(void Function() onTap) async {
    _onTap = onTap;
    try {
      return await (_initialization ??= _initializeOnce());
    } catch (_) {
      // 初始化失败允许重试，不把一个失败的 Future 永久缓存下来。
      _initialization = null;
      rethrow;
    }
  }

  Future<bool> _initializeOnce() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError('Reminders currently support Android and iOS');
    }
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_moon'),
        // 初始化绝不自行弹授权框；先让用户看到页面中的礼貌说明。
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == payload) _onTap?.call();
      },
    );
    // 提前建立渠道，以便权限检查也能发现用户单独关闭了这个渠道。
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            channelId,
            _strings.reminderChannelName,
            description: _strings.reminderChannelDescription,
            importance: Importance.high,
          ),
        );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload == payload;
  }

  @override
  Future<bool> isPermissionGranted() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!;
      if (await android.areNotificationsEnabled() != true) return false;
      final channels = await android.getNotificationChannels();
      return !(channels ?? []).any(
        (channel) =>
            channel.id == channelId && channel.importance == Importance.none,
      );
    }
    final permissions = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()!
        .checkPermissions();
    return permissions?.isEnabled == true &&
        permissions?.isAlertEnabled == true;
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!
          .requestNotificationsPermission();
    } else {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()!
          .requestPermissions(alert: true, sound: true, badge: false);
    }
    // 用户可能只关闭某个渠道/提示类型，所以最终结果再次向系统读取。
    return isPermissionGranted();
  }

  @override
  Future<void> openSystemSettings() async {
    if (await _plugin.openAppNotificationSettings() != true) {
      throw StateError('Notification settings could not be opened');
    }
  }

  @override
  Future<void> scheduleDaily(ReminderSettings settings) async {
    // 每次调度都读取设备时区；从系统设置返回或旅行后重开 App 时会重排。
    final zone = await FlutterTimezone.getLocalTimezone();
    final location = tz.getLocation(zone.identifier);
    await _plugin.zonedSchedule(
      id: dailyId,
      title: _strings.dailyNotificationTitle,
      body: _strings.dailyNotificationBody,
      scheduledDate: nextReminderTime(
        tz.TZDateTime.now(location),
        settings.hour,
        settings.minute,
      ),
      notificationDetails: _details,
      // 普通记录提醒使用系统允许的非精确调度，不额外索要闹钟权限。
      // Android 节电时可能延迟，页面及验收说明明确告知这一边界。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
    // 同一个 ID 代表同一项每日任务，修改时间会替换旧任务，不叠加通知。
  }

  @override
  Future<void> cancelDaily() => _plugin.cancel(id: dailyId);

  @override
  Future<void> showTest() => _plugin.show(
    id: testId,
    title: _strings.testNotificationTitle,
    body: _strings.testNotificationBody,
    notificationDetails: _details,
    payload: payload,
  );

  @override
  void dispose() => _onTap = null;
}
