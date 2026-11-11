/// 用户希望“每天几点提醒”的设置；不存储梦境正文，也不存储系统权限。
///
/// 系统权限随时可能被用户撤销，必须实时查询，不能相信磁盘中的旧布尔值。
/// enabled 表示用户的意愿；真正能够提醒，还需要系统允许通知。
class ReminderSettings {
  ReminderSettings({
    this.enabled = false,
    this.hour = 8,
    this.minute = 0,
    this.noticeSeen = false,
    this.menuHintSeen = false,
    this.weeklyEnabled = false,
    this.weeklyWeekday = DateTime.sunday,
    this.weeklyHour = 21,
    this.weeklyMinute = 0,
  }) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
    RangeError.checkValueInInterval(weeklyWeekday, 1, 7, 'weeklyWeekday');
    RangeError.checkValueInInterval(weeklyHour, 0, 23, 'weeklyHour');
    RangeError.checkValueInInterval(weeklyMinute, 0, 59, 'weeklyMinute');
  }

  final bool enabled;
  final int hour;
  final int minute;
  final bool noticeSeen;
  // 菜单入口教学与通知授权说明是两个独立步骤：看过菜单提示，
  // 不代表已经读过通知用途或愿意授权，不能复用 noticeSeen。
  final bool menuHintSeen;
  // 两项提醒共享系统授权，用户意愿与发送时间分别保存，互不自动开启。
  // 星期沿用 Dart 的 1（周一）到 7（周日），只在平台插件边界转换。
  final bool weeklyEnabled;
  final int weeklyWeekday;
  final int weeklyHour;
  final int weeklyMinute;

  String get weeklyTimeLabel =>
      '${weeklyHour.toString().padLeft(2, '0')}:${weeklyMinute.toString().padLeft(2, '0')}';

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? noticeSeen,
    bool? menuHintSeen,
    bool? weeklyEnabled,
    int? weeklyWeekday,
    int? weeklyHour,
    int? weeklyMinute,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    noticeSeen: noticeSeen ?? this.noticeSeen,
    menuHintSeen: menuHintSeen ?? this.menuHintSeen,
    weeklyEnabled: weeklyEnabled ?? this.weeklyEnabled,
    weeklyWeekday: weeklyWeekday ?? this.weeklyWeekday,
    weeklyHour: weeklyHour ?? this.weeklyHour,
    weeklyMinute: weeklyMinute ?? this.weeklyMinute,
  );

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'noticeSeen': noticeSeen,
    'menuHintSeen': menuHintSeen,
    'weeklyEnabled': weeklyEnabled,
    'weeklyWeekday': weeklyWeekday,
    'weeklyHour': weeklyHour,
    'weeklyMinute': weeklyMinute,
  };

  /// 配置损坏时报告错误，不能静默覆盖成默认值或擅自开启通知。
  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    if (json['enabled'] is! bool ||
        json['hour'] is! int ||
        json['minute'] is! int ||
        json['noticeSeen'] is! bool ||
        (json.containsKey('menuHintSeen') && json['menuHintSeen'] is! bool)) {
      throw const FormatException('Invalid reminder settings');
    }
    // 只对缺失的新字段使用默认值；显式 null/错误类型不能掩盖配置损坏。
    for (final key in [
      'weeklyEnabled',
      'weeklyWeekday',
      'weeklyHour',
      'weeklyMinute',
    ]) {
      if (json.containsKey(key) &&
          (key == 'weeklyEnabled' ? json[key] is! bool : json[key] is! int)) {
        throw const FormatException('Invalid weekly reminder settings');
      }
    }
    return ReminderSettings(
      weeklyEnabled: json['weeklyEnabled'] as bool? ?? false,
      weeklyWeekday: json['weeklyWeekday'] as int? ?? DateTime.sunday,
      weeklyHour: json['weeklyHour'] as int? ?? 21,
      weeklyMinute: json['weeklyMinute'] as int? ?? 0,
      enabled: json['enabled'] as bool,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      noticeSeen: json['noticeSeen'] as bool,
      // 旧版没有菜单教学字段，升级后应展示一次新入口提示。
      // 只对缺失字段补默认值；显式 null 或其他类型仍属于配置损坏，
      // 不能因此覆盖用户已经保存的提醒开关、时间和授权说明状态。
      menuHintSeen: json['menuHintSeen'] as bool? ?? false,
    );
  }
}
