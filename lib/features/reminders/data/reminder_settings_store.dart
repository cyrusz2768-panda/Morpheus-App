import 'dart:convert';
import 'dart:io';

import 'package:morpheus/features/reminders/domain/reminder_settings.dart';
import 'package:path_provider/path_provider.dart';

/// Controller 只依赖接口；单元测试可以注入内存替身，避免访问真实设置。
abstract interface class IReminderSettingsStore {
  Future<ReminderSettings> read();
  Future<void> write(ReminderSettings settings);
}

/// 小量配置使用私有目录中的 JSON；梦境正文仍由原来的 SQLite 保存。
///
/// resolveFile 可注入临时文件，因此可以真正测试“关闭后重新读取”，
/// 同时不读取开发者自己的梦境数据库或提醒设置。
class FileReminderSettingsStore implements IReminderSettingsStore {
  FileReminderSettingsStore({Future<File> Function()? resolveFile})
    : _resolveFile = resolveFile ?? _defaultFile;

  final Future<File> Function() _resolveFile;

  static Future<File> _defaultFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/settings/reminders.json');
  }

  @override
  Future<ReminderSettings> read() async {
    final file = await _resolveFile();
    if (!await file.exists()) return ReminderSettings();
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic> ||
        json['notifications'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid notifications configuration');
    }
    return ReminderSettings.fromJson(
      json['notifications'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> write(ReminderSettings settings) async {
    final file = await _resolveFile();
    await file.parent.create(recursive: true);
    // Controller 串行执行所有设置变更。先完整写入临时文件并 flush，
    // 再原子重命名，避免中途退出把上一份有效配置截断成半个 JSON。
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'notifications': settings.toJson()}),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
