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
  }) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
  }

  final bool enabled;
  final int hour;
  final int minute;
  final bool noticeSeen;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ReminderSettings copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    bool? noticeSeen,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    noticeSeen: noticeSeen ?? this.noticeSeen,
  );

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'noticeSeen': noticeSeen,
  };

  /// 配置损坏时报告错误，不能静默覆盖成默认值或擅自开启通知。
  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    if (json['enabled'] is! bool ||
        json['hour'] is! int ||
        json['minute'] is! int ||
        json['noticeSeen'] is! bool) {
      throw const FormatException('Invalid reminder settings');
    }
    return ReminderSettings(
      enabled: json['enabled'] as bool,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      noticeSeen: json['noticeSeen'] as bool,
    );
  }
}
