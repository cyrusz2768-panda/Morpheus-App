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

/// 每周重复使用日历构造，不能把一周直接当成固定的 168 小时。
/// 在夏令时变化、跨月和跨年时，仍以用户选择的当地星期与时间为准。
tz.TZDateTime nextWeeklyReminderTime(
  tz.TZDateTime now,
  int weekday,
  int hour,
  int minute,
) {
  RangeError.checkValueInInterval(weekday, 1, 7, 'weekday');
  RangeError.checkValueInInterval(hour, 0, 23, 'hour');
  RangeError.checkValueInInterval(minute, 0, 59, 'minute');
  var offset = (weekday - now.weekday + 7) % 7;
  while (true) {
    final candidate = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day + offset,
      hour,
      minute,
    );
    // 夏令时跳过的本地时间会被 TZDateTime 归一成另一个小时。
    // 插件以首次日期的时分作为永久重复模板，不能把 02:30 固化成 03:30；
    // 此时寻找下一个存在该时分的星期作为模板，保留用户的原时间选择。
    if (candidate.isAfter(now) &&
        candidate.weekday == weekday &&
        candidate.hour == hour &&
        candidate.minute == minute) {
      return candidate;
    }
    offset += 7;
  }
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
  static const weeklyId = 1103;
  static const weeklyTestId = 1104;
  static const weeklyPayload = 'morpheus:weekly-statistics';

  static ReminderDestination? _destination(String? value) => switch (value) {
    payload => ReminderDestination.today,
    weeklyPayload => ReminderDestination.weeklyStatistics,
    _ => null,
  };

  final FlutterLocalNotificationsPlugin _plugin;
  Future<ReminderDestination?>? _initialization;
  void Function(ReminderDestination)? _onTap;

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
  Future<ReminderDestination?> initialize(
    void Function(ReminderDestination) onTap,
  ) async {
    _onTap = onTap;
    try {
      return await (_initialization ??= _initializeOnce());
    } catch (_) {
      // 初始化失败允许重试，不把一个失败的 Future 永久缓存下来。
      _initialization = null;
      rethrow;
    }
  }

  Future<ReminderDestination?> _initializeOnce() async {
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
        final target = _destination(response.payload);
        if (target != null) _onTap?.call(target);
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
    return launch?.didNotificationLaunchApp == true
        ? _destination(launch?.notificationResponse?.payload)
        : null;
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
  Future<void> scheduleWeekly(ReminderSettings settings) async {
    final zone = await FlutterTimezone.getLocalTimezone();
    final location = tz.getLocation(zone.identifier);
    await _plugin.zonedSchedule(
      id: weeklyId,
      title: _strings.weeklyNotificationTitle,
      body: _strings.weeklyNotificationBody,
      scheduledDate: nextWeeklyReminderTime(
        tz.TZDateTime.now(location),
        settings.weeklyWeekday,
        settings.weeklyHour,
        settings.weeklyMinute,
      ),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      // 重复任务不能固化首次发送的日期。点击时由 App 选取最新自然周。
      payload: weeklyPayload,
    );
  }

  @override
  Future<void> cancelWeekly() => _plugin.cancel(id: weeklyId);

  @override
  Future<void> showTest({bool weekly = false}) => _plugin.show(
    id: weekly ? weeklyTestId : testId,
    title: weekly
        ? _strings.weeklyNotificationTitle
        : _strings.testNotificationTitle,
    body: weekly
        ? _strings.weeklyNotificationBody
        : _strings.testNotificationBody,
    notificationDetails: _details,
    payload: weekly ? weeklyPayload : payload,
  );

  @override
  void dispose() => _onTap = null;
}
