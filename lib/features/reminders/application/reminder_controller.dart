import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/reminders/data/local_reminder_notifications.dart';
import 'package:morpheus/features/reminders/data/reminder_notifications.dart';
import 'package:morpheus/features/reminders/data/reminder_settings_store.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';

final reminderSettingsStoreProvider = Provider<IReminderSettingsStore>(
  (ref) => FileReminderSettingsStore(),
);
final reminderNotificationsProvider = Provider<IReminderNotifications>((ref) {
  final service = LocalReminderNotifications();
  ref.onDispose(service.dispose);
  return service;
});
final reminderControllerProvider =
    NotifierProvider<ReminderController, ReminderState>(ReminderController.new);

/// 界面状态不可变；settings 为 null 表示尚未读到可信配置，暂不允许修改。
class ReminderState {
  const ReminderState({
    this.settings,
    this.isLoading = true,
    this.isBusy = false,
    this.permissionGranted = false,
    this.error,
    this.tapSequence = 0,
  });

  final ReminderSettings? settings;
  final bool isLoading;
  final bool isBusy;
  final bool permissionGranted;
  final String? error;
  // 每次通知点击递增。导航由 App 层处理，Controller 不持有 BuildContext。
  final int tapSequence;

  ReminderState copyWith({
    ReminderSettings? settings,
    bool? isLoading,
    bool? isBusy,
    bool? permissionGranted,
    String? error,
    int? tapSequence,
  }) => ReminderState(
    settings: settings ?? this.settings,
    isLoading: isLoading ?? this.isLoading,
    isBusy: isBusy ?? this.isBusy,
    permissionGranted: permissionGranted ?? this.permissionGranted,
    error: error,
    tapSequence: tapSequence ?? this.tapSequence,
  );
}

class ReminderController extends Notifier<ReminderState> {
  bool _working = false;
  bool _launchHandled = false;

  @override
  ReminderState build() {
    Future<void>.microtask(() {
      if (ref.mounted) unawaited(load());
    });
    return const ReminderState();
  }

  IReminderNotifications get _notifications =>
      ref.read(reminderNotificationsProvider);
  IReminderSettingsStore get _store => ref.read(reminderSettingsStoreProvider);

  /// 启动/返回前台时同步设置与权限，但从不自动申请权限。
  Future<void> load() async {
    if (_working || !ref.mounted) return;
    _working = true;
    state = state.copyWith(isLoading: true);
    try {
      final settings = await _store.read();
      if (!ref.mounted) return;
      final launched = await _notifications.initialize(() {
        if (ref.mounted) {
          state = state.copyWith(
            tapSequence: state.tapSequence + 1,
            error: state.error,
          );
        }
      });
      final granted = await _notifications.isPermissionGranted();
      await _applySchedule(settings, granted);
      if (!ref.mounted) return;
      state = state.copyWith(settings: settings, permissionGranted: granted);
      if (launched && !_launchHandled) {
        _launchHandled = true;
        state = state.copyWith(tapSequence: state.tapSequence + 1);
      }
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(error: '提醒设置暂时无法加载，请重试。梦境记录仍可正常使用。');
      }
    } finally {
      _working = false;
      if (ref.mounted) {
        state = state.copyWith(isLoading: false, error: state.error);
      }
    }
  }

  Future<void> _applySchedule(ReminderSettings settings, bool granted) =>
      settings.enabled && granted
      ? _notifications.scheduleDaily(settings)
      : _notifications.cancelDaily();

  /// 一次只允许一个写入/授权操作，快速连点不会让旧设置覆盖新设置。
  Future<bool> _run(Future<void> Function() operation) async {
    if (_working || state.settings == null || !ref.mounted) return false;
    _working = true;
    state = state.copyWith(isBusy: true);
    try {
      await operation();
      return ref.mounted && state.error == null;
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(error: '操作未完成，请重试；原来的提醒设置仍然保留。');
      }
      return false;
    } finally {
      _working = false;
      if (ref.mounted) {
        state = state.copyWith(isBusy: false, error: state.error);
      }
    }
  }

  /// 先持久化“已读说明”，两种选择都会记住；仅明确同意时申请系统授权。
  Future<bool> acknowledgeNotice({required bool requestPermission}) =>
      _run(() async {
        final next = state.settings!.copyWith(noticeSeen: true);
        await _store.write(next);
        if (!ref.mounted) return;
        state = state.copyWith(settings: next, isBusy: true);
        if (requestPermission) await _requestPermission();
      });

  Future<void> _requestPermission() async {
    final granted = await _notifications.requestPermission();
    if (!ref.mounted) return;
    state = state.copyWith(
      permissionGranted: granted,
      error: granted ? null : '系统通知尚未开启。您可以稍后在系统设置中允许通知。',
    );
    await _applySchedule(state.settings!, granted);
  }

  Future<bool> requestPermission() => _run(_requestPermission);
  Future<bool> openSystemSettings() => _run(_notifications.openSystemSettings);

  Future<bool> setTime(int hour, int minute) => _run(() async {
    await _commit(state.settings!.copyWith(hour: hour, minute: minute));
  });

  Future<bool> setEnabled(bool enabled) => _run(() async {
    if (enabled) {
      final granted =
          await _notifications.isPermissionGranted() ||
          await _notifications.requestPermission();
      if (!ref.mounted) return;
      state = state.copyWith(permissionGranted: granted);
      if (!granted) {
        state = state.copyWith(error: '开启每日提醒需要允许系统通知，请选择“去系统设置”。');
        return;
      }
    }
    await _commit(state.settings!.copyWith(enabled: enabled));
  });

  /// 调度和文件不是同一个数据库事务，所以保存失败时补偿恢复旧调度。
  /// 界面只有在两个步骤都成功后才确认新设置，避免显示一个没生效的时间。
  Future<void> _commit(ReminderSettings next) async {
    final previous = state.settings!;
    final granted = await _notifications.isPermissionGranted();
    try {
      await _applySchedule(next, granted);
      await _store.write(next);
    } catch (_) {
      try {
        await _applySchedule(previous, granted);
      } catch (_) {
        // 两次系统调用均失败时，仍保留磁盘中的用户意愿，并明确显示错误。
        // 用户可重试或重新打开页面，load() 会按保存的设置重新同步系统。
      }
      rethrow;
    }
    if (ref.mounted) {
      state = state.copyWith(settings: next, permissionGranted: granted);
    }
  }

  Future<bool> showTest() => _run(() async {
    final granted = await _notifications.isPermissionGranted();
    if (!ref.mounted) return;
    state = state.copyWith(permissionGranted: granted);
    if (!granted) {
      state = state.copyWith(error: '请先允许系统通知，再发送测试通知。');
      return;
    }
    await _notifications.showTest();
  });
}
