import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/l10n/app_text.dart';

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
        title: Text(context.l10n.notificationNoticeTitle),
        content: Text(context.l10n.notificationNoticeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.later),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.allowNotifications),
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
      helpText: context.l10n.selectReminderTime,
      cancelText: context.l10n.cancel,
      confirmText: context.l10n.confirm,
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
      appBar: AppBar(title: Text(context.l10n.dailyReminder)),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(context.l10n.reminderPrompt),
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
                      child: Text(context.l10n.retryLoad),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (settings != null) ...[
                    SwitchListTile(
                      key: const Key('daily-reminder-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.dailyReminder),
                      subtitle: Text(
                        settings.enabled
                            ? state.permissionGranted
                                  ? context.l10n.reminderDailyAt(
                                      settings.timeLabel,
                                    )
                                  : context.l10n.reminderWaitingPermission
                            : context.l10n.reminderDisabled,
                      ),
                      value: settings.enabled,
                      onChanged: editable ? controller.setEnabled : null,
                    ),
                    ListTile(
                      key: const Key('reminder-time-tile'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.reminderTime),
                      trailing: Text(
                        settings.timeLabel,
                        key: const Key('reminder-time'),
                      ),
                      onTap: editable ? _chooseTime : null,
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.systemNotifications),
                      subtitle: Text(
                        state.permissionGranted
                            ? context.l10n.notificationsAllowed
                            : context.l10n.notificationsNotAllowed,
                      ),
                    ),
                    if (!state.permissionGranted)
                      OutlinedButton(
                        onPressed: editable
                            ? controller.requestPermission
                            : null,
                        child: Text(context.l10n.requestNotificationPermission),
                      ),
                    TextButton(
                      onPressed: editable
                          ? controller.openSystemSettings
                          : null,
                      child: Text(context.l10n.openSystemSettings),
                    ),
                    OutlinedButton.icon(
                      key: const Key('test-notification-button'),
                      onPressed: editable ? controller.showTest : null,
                      icon: const Icon(Icons.notifications_outlined),
                      label: Text(context.l10n.sendTestNotification),
                    ),
                    const SizedBox(height: 12),
                    Text(context.l10n.reminderAutoSaveNote),
                    const SizedBox(height: 8),
                    Text(context.l10n.reminderSystemLimitNote),
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
