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

  Future<void> _chooseTime({bool weekly = false}) async {
    final settings = ref.read(reminderControllerProvider).settings!;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: weekly ? settings.weeklyHour : settings.hour,
        minute: weekly ? settings.weeklyMinute : settings.minute,
      ),
      helpText: weekly
          ? context.l10n.weeklyReminderTime
          : context.l10n.selectReminderTime,
      cancelText: context.l10n.cancel,
      confirmText: context.l10n.confirm,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (mounted && time != null) {
      final controller = ref.read(reminderControllerProvider.notifier);
      if (weekly) {
        await controller.setWeeklyTime(time.hour, time.minute);
      } else {
        await controller.setTime(time.hour, time.minute);
      }
    }
  }

  Future<void> _chooseWeekday() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.weeklyReminderDay),
        children: [
          for (var day = 1; day <= 7; day++)
            SimpleDialogOption(
              key: Key('weekly-day-$day'),
              onPressed: () => Navigator.pop(context, day),
              child: Text(context.l10n.weekdayLabel('$day')),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    );
    if (mounted && selected != null) {
      await ref
          .read(reminderControllerProvider.notifier)
          .setWeeklyWeekday(selected);
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
      appBar: AppBar(title: Text(context.l10n.notificationSettings)),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (state.error != null) ...[
                    Text(
                      state.error!,
                      key: const Key('reminder-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: state.isBusy ? null : controller.load,
                          child: Text(context.l10n.retryLoad),
                        ),
                        // 权限补救只在失败时出现，不另占一栏常驻系统状态。
                        // 开关仍通过 Controller 查询/申请权限，页面不调用插件。
                        if (settings != null && !state.permissionGranted)
                          TextButton(
                            key: const Key('reminder-permission-settings'),
                            onPressed: editable
                                ? controller.openSystemSettings
                                : null,
                            child: Text(context.l10n.openSystemSettings),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (settings != null) ...[
                    _ReminderSection(
                      key: const Key('daily-reminder-section'),
                      title: context.l10n.dailyReminder,
                      enabled: settings.enabled,
                      switchKey: const Key('daily-reminder-switch'),
                      onChanged: editable ? controller.setEnabled : null,
                      children: [
                        _ReminderOption(
                          key: const Key('reminder-time-tile'),
                          title: context.l10n.reminderTime,
                          value: settings.timeLabel,
                          onTap: editable ? _chooseTime : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _ReminderSection(
                      key: const Key('weekly-reminder-section'),
                      title: context.l10n.weeklyReminder,
                      enabled: settings.weeklyEnabled,
                      switchKey: const Key('weekly-reminder-switch'),
                      onChanged: editable ? controller.setWeeklyEnabled : null,
                      children: [
                        _ReminderOption(
                          key: const Key('weekly-reminder-day-tile'),
                          title: context.l10n.weeklyReminderDay,
                          value: context.l10n.weekdayLabel(
                            '${settings.weeklyWeekday}',
                          ),
                          onTap: editable ? _chooseWeekday : null,
                        ),
                        _ReminderOption(
                          key: const Key('weekly-reminder-time-tile'),
                          title: context.l10n.weeklyReminderTime,
                          value: settings.weeklyTimeLabel,
                          onTap: editable
                              ? () => _chooseTime(weekly: true)
                              : null,
                        ),
                      ],
                    ),
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

/// 每类提醒的标题在卡片外，内部首行始终保留开关。
/// 细项是否展开直接由已保存的 enabled 决定：保存失败时不提前折叠，
/// 关闭也只隐藏控件，不清空原时间，重新开启即可继续使用上次选择。
class _ReminderSection extends StatelessWidget {
  const _ReminderSection({
    super.key,
    required this.title,
    required this.enabled,
    required this.switchKey,
    required this.onChanged,
    required this.children,
  });

  final String title;
  final bool enabled;
  final Key switchKey;
  final ValueChanged<bool>? onChanged;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SwitchListTile(
              key: switchKey,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: Text(context.l10n.reminderMessageNotifications),
              value: enabled,
              onChanged: onChanged,
            ),
            // 不把隐藏行留在语义树/焦点链中，关闭后不能误点到时间选择器。
            if (enabled)
              for (final child in children) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                child,
              ],
          ],
        ),
      ),
    ],
  );
}

class _ReminderOption extends StatelessWidget {
  const _ReminderOption({
    super.key,
    required this.title,
    required this.value,
    required this.onTap,
  });
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, size: 20),
      ],
    ),
    onTap: onTap,
  );
}
