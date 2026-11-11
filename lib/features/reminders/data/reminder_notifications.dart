import 'package:morpheus/features/reminders/domain/reminder_settings.dart';

enum ReminderDestination { today, weeklyStatistics }

/// 隔离平台插件：页面和业务测试不直接操作 Android/iOS 的通知系统。
abstract interface class IReminderNotifications {
  /// 返回本次提醒冷启动的目标；普通启动返回 null；onTap 处理运行中的点击。
  Future<ReminderDestination?> initialize(
    void Function(ReminderDestination) onTap,
  );
  Future<bool> isPermissionGranted();
  Future<bool> requestPermission();
  Future<void> openSystemSettings();
  Future<void> scheduleDaily(ReminderSettings settings);
  Future<void> cancelDaily();
  Future<void> scheduleWeekly(ReminderSettings settings);
  Future<void> cancelWeekly();
  Future<void> showTest({bool weekly = false});
  void dispose();
}
