import 'package:morpheus/features/reminders/domain/reminder_settings.dart';

/// 隔离平台插件：页面和业务测试不直接操作 Android/iOS 的通知系统。
abstract interface class IReminderNotifications {
  /// 返回这次冷启动是否由本应用的提醒触发；onTap 处理运行中的点击。
  Future<bool> initialize(void Function() onTap);
  Future<bool> isPermissionGranted();
  Future<bool> requestPermission();
  Future<void> openSystemSettings();
  Future<void> scheduleDaily(ReminderSettings settings);
  Future<void> cancelDaily();
  Future<void> showTest();
  void dispose();
}
