import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';

class ReminderSettingsPage extends ConsumerStatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  ConsumerState<ReminderSettingsPage> createState() =>
      _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends ConsumerState<ReminderSettingsPage> {
  bool _noticeShown = false;

  Future<void> _showNotice() async {
    if (!mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('notification-permission-notice'),
        title: const Text('关于提醒通知'),
        content: const Text(
          '为了在您设定的时间提醒记录梦境，需要您允许系统通知。'
          '\n\n如果您愿意，请在接下来的系统提示中允许通知。'
          '您也可以稍后开启，这不会影响记录和查看梦境。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('允许通知'),
          ),
        ],
      ),
    );
    if (!mounted || allow == null) return;
    await ref
        .read(reminderControllerProvider.notifier)
        .acknowledgeNotice(requestPermission: allow);
  }

  Future<void> _chooseTime() async {
    final settings = ref.read(reminderControllerProvider).settings!;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.hour, minute: settings.minute),
      helpText: '选择每日提醒时间',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (mounted && time != null) {
      await ref
          .read(reminderControllerProvider.notifier)
          .setTime(time.hour, time.minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reminderControllerProvider);
    final controller = ref.read(reminderControllerProvider.notifier);
    final settings = state.settings;
    // 首次加载完成后再弹说明，避免 build 中直接 showDialog；标志先置位，
    // 防止异步状态更新在同一次访问中排队弹出多个相同对话框。
    if (!state.isLoading &&
        settings != null &&
        !settings.noticeSeen &&
        !_noticeShown) {
      _noticeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNotice());
    }
    final editable = settings != null && !state.isLoading && !state.isBusy;
    return Scaffold(
      appBar: AppBar(title: const Text('每日提醒')),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('给醒来的自己留一点时间，记下还没散去的梦。'),
                  const SizedBox(height: 20),
                  if (state.error != null) ...[
                    Text(
                      state.error!,
                      key: const Key('reminder-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    TextButton(
                      onPressed: state.isBusy ? null : controller.load,
                      child: const Text('重试加载'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (settings != null) ...[
                    SwitchListTile(
                      key: const Key('daily-reminder-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('每日提醒'),
                      subtitle: Text(
                        settings.enabled
                            ? state.permissionGranted
                                  ? '每天 ${settings.timeLabel} 提醒记录梦境'
                                  : '已开启，等待系统通知权限'
                            : '尚未开启',
                      ),
                      value: settings.enabled,
                      onChanged: editable ? controller.setEnabled : null,
                    ),
                    ListTile(
                      key: const Key('reminder-time-tile'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('提醒时间'),
                      trailing: Text(
                        settings.timeLabel,
                        key: const Key('reminder-time'),
                      ),
                      onTap: editable ? _chooseTime : null,
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('系统通知'),
                      subtitle: Text(
                        state.permissionGranted ? '已允许通知' : '尚未允许通知',
                      ),
                    ),
                    if (!state.permissionGranted)
                      OutlinedButton(
                        onPressed: editable
                            ? controller.requestPermission
                            : null,
                        child: const Text('申请通知权限'),
                      ),
                    TextButton(
                      onPressed: editable
                          ? controller.openSystemSettings
                          : null,
                      child: const Text('去系统设置'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('test-notification-button'),
                      onPressed: editable ? controller.showTest : null,
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('发送测试通知'),
                    ),
                    const SizedBox(height: 12),
                    const Text('设置会自动保存。测试通知不会开启每日提醒。'),
                    const SizedBox(height: 8),
                    const Text('提醒可能受系统节电、静音或专注模式影响。Android 的普通提醒可能稍有延迟。'),
                  ],
                  if (state.isBusy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
      ),
    );
  }
}
