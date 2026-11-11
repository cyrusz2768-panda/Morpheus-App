import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/reminders/data/local_reminder_notifications.dart';
import 'package:morpheus/features/reminders/data/reminder_notifications.dart';
import 'package:morpheus/features/reminders/data/reminder_settings_store.dart';
import 'package:morpheus/features/reminders/domain/reminder_settings.dart';
import 'package:morpheus/l10n/app_text.dart';

final reminderSettingsStoreProvider = Provider<IReminderSettingsStore>(
  (ref) => FileReminderSettingsStore(),
);
final reminderNotificationsProvider = Provider<IReminderNotifications>((ref) {
  final service = LocalReminderNotifications(
    strings: ref.read(appLocalizationsProvider),
  );
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
    this.destination = ReminderDestination.today,
  });

  final ReminderSettings? settings;
  final bool isLoading;
  final bool isBusy;
  final bool permissionGranted;
  final String? error;
  // 每次通知点击递增。导航由 App 层处理，Controller 不持有 BuildContext。
  final int tapSequence;
  final ReminderDestination destination;

  ReminderState copyWith({
    ReminderSettings? settings,
    bool? isLoading,
    bool? isBusy,
    bool? permissionGranted,
    String? error,
    int? tapSequence,
    ReminderDestination? destination,
  }) => ReminderState(
    settings: settings ?? this.settings,
    isLoading: isLoading ?? this.isLoading,
    isBusy: isBusy ?? this.isBusy,
    permissionGranted: permissionGranted ?? this.permissionGranted,
    error: error,
    tapSequence: tapSequence ?? this.tapSequence,
    destination: destination ?? this.destination,
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
      final beforeInitialization = state.tapSequence;
      final launched = await _notifications.initialize((destination) {
        if (ref.mounted) {
          state = state.copyWith(
            tapSequence: state.tapSequence + 1,
            destination: destination,
            error: state.error,
          );
        }
      });
      if (!ref.mounted) return;
      if (launched != null && !_launchHandled) {
        _launchHandled = true;
        // 初始化期间若已收到更新的热点击，不让旧冷启动目标覆盖它。
        if (state.tapSequence == beforeInitialization) {
          state = state.copyWith(
            tapSequence: state.tapSequence + 1,
            destination: launched,
          );
        }
      }
      final settings = await _store.read();
      final granted = await _notifications.isPermissionGranted();
      await _applySchedule(settings, granted);
      if (!ref.mounted) return;
      state = state.copyWith(settings: settings, permissionGranted: granted);
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          error: ref.read(appLocalizationsProvider).reminderLoadFailed,
        );
      }
    } finally {
      _working = false;
      if (ref.mounted) {
        state = state.copyWith(isLoading: false, error: state.error);
      }
    }
  }

  Future<void> _applySchedule(ReminderSettings settings, bool granted) async {
    // 两项操作均尝试执行：某项平台故障不应阻止另一项关闭/同步。
    // Future.wait 会等待两者结束再报告错误，补偿恢复也不会与旧调用并发。
    await Future.wait([
      settings.enabled && granted
          ? _notifications.scheduleDaily(settings)
          : _notifications.cancelDaily(),
      settings.weeklyEnabled && granted
          ? _notifications.scheduleWeekly(settings)
          : _notifications.cancelWeekly(),
    ]);
  }

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
        state = state.copyWith(
          error: ref.read(appLocalizationsProvider).reminderOperationFailed,
        );
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

  /// 菜单教学只记录“已发现入口”，不表示用户同意接收通知。
  /// 仍走同一串行写入入口，避免与修改提醒时间同时保存时丢失设置；
  /// 只有文件保存成功才更新界面，失败后下次仍会展示教学以便重试。
  /// 此处不调用 _commit：纯界面教学不应查询/请求权限或重排已有提醒。
  Future<bool> acknowledgeMenuHint() => _run(() async {
    final next = state.settings!.copyWith(menuHintSeen: true);
    await _store.write(next);
    if (!ref.mounted) return;
    state = state.copyWith(settings: next);
  });

  Future<void> _requestPermission() async {
    final granted = await _notifications.requestPermission();
    if (!ref.mounted) return;
    state = state.copyWith(
      permissionGranted: granted,
      error: granted
          ? null
          : ref.read(appLocalizationsProvider).reminderPermissionDenied,
    );
    await _applySchedule(state.settings!, granted);
  }

  Future<bool> requestPermission() => _run(_requestPermission);
  Future<bool> openSystemSettings() => _run(_notifications.openSystemSettings);

  Future<bool> setTime(int hour, int minute) => _run(() async {
    await _commit(state.settings!.copyWith(hour: hour, minute: minute));
  });

  Future<bool> setWeeklyTime(int hour, int minute) => _run(() async {
    await _commit(
      state.settings!.copyWith(weeklyHour: hour, weeklyMinute: minute),
    );
  });

  Future<bool> setWeeklyWeekday(int weekday) => _run(() async {
    await _commit(state.settings!.copyWith(weeklyWeekday: weekday));
  });

  Future<bool> setWeeklyEnabled(bool enabled) =>
      _setEnabled(enabled, weekly: true);
  Future<bool> setEnabled(bool enabled) => _setEnabled(enabled, weekly: false);

  Future<bool> _setEnabled(bool enabled, {required bool weekly}) =>
      _run(() async {
        if (enabled) {
          final granted =
              await _notifications.isPermissionGranted() ||
              await _notifications.requestPermission();
          if (!ref.mounted) return;
          state = state.copyWith(permissionGranted: granted);
          if (!granted) {
            state = state.copyWith(
              error: ref
                  .read(appLocalizationsProvider)
                  .reminderEnableNeedsPermission,
            );
            return;
          }
        }
        await _commit(
          weekly
              ? state.settings!.copyWith(weeklyEnabled: enabled)
              : state.settings!.copyWith(enabled: enabled),
        );
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

  Future<bool> showTest({bool weekly = false}) => _run(() async {
    final granted = await _notifications.isPermissionGranted();
    if (!ref.mounted) return;
    state = state.copyWith(permissionGranted: granted);
    if (!granted) {
      state = state.copyWith(
        error: ref
            .read(appLocalizationsProvider)
            .testNotificationNeedsPermission,
      );
      return;
    }
    await _notifications.showTest(weekly: weekly);
  });
}
