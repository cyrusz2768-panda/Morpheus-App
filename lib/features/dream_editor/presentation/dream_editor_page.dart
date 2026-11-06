import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_history/application/dream_history_provider.dart';

/// The first visible feature of the practice application.
///
/// This is a ConsumerStatefulWidget for two reasons:
/// 1. Riverpod's `ref` is needed to watch and call the controller.
/// 2. TextEditingController and app lifecycle observation have lifecycles of
///    their own and therefore must be created/disposed by a State object.
class DreamEditorPage extends ConsumerStatefulWidget {
  const DreamEditorPage({super.key});

  @override
  ConsumerState<DreamEditorPage> createState() => _DreamEditorPageState();
}

class _DreamEditorPageState extends ConsumerState<DreamEditorPage>
    with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();

  // 一次只处理一个日期/历史导航操作，防止快速连点弹出多个页面或并发切日。
  // 这是页面交互状态；正文、保存结果与所选日期仍由 Controller 管理。
  bool _isNavigating = false;

  Future<void> _openReminders() async {
    if (_isNavigating) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      // 与打开历史一样，离开编辑页前等待最新草稿。权限弹窗可能让 App
      // 进入 inactive 状态，所以先确保正文已经保存，再处理提醒设置。
      do {
        final saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!mounted) return;
        if (!saved) {
          _showNavigationFailure();
          return;
        }
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      await context.push<void>('/reminders');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _chooseDate() async {
    if (_isNavigating) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      final date = ref.read(dreamEditorControllerProvider).date;
      final today = DreamEntry.dateOnly(DateTime.now());
      final firstDate = DateTime(1900);
      // initialDate 必须位于选择器范围内。若系统时间被调整，仍给选择器
      // 一个合法初始日期；原记录的日期不会因此被悄悄改写。
      final initialDate = date.isAfter(today)
          ? today
          : date.isBefore(firstDate)
          ? firstDate
          : date;
      final chosen = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: today,
        helpText: '选择梦境日期',
        cancelText: '取消',
        confirmText: '确定',
      );
      if (mounted && chosen != null) await _applyDate(chosen);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _openHistory() async {
    if (_isNavigating) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      // 等待真正写入后再进入列表，避免用户刚输入的梦境还没出现在历史中。
      do {
        final saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!mounted) return;
        if (!saved) {
          _showNavigationFailure();
          return;
        }
        // await 让出执行权期间，输入法可能刚好提交最后一段文字。导航前再
        // 确认一次；这个最终检查与 push 之间没有 await，不留未提交窗口。
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      ref.invalidate(dreamHistoryProvider);
      final date = await context.push<DateTime>('/history');
      if (mounted && date != null) await _applyDate(date);
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _backToToday() async {
    if (_isNavigating) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      await _applyDate(DreamEntry.dateOnly(DateTime.now()));
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _applyDate(DateTime date) async {
    final selected = await ref
        .read(dreamEditorControllerProvider.notifier)
        .selectDate(date);
    if (mounted && !selected) _showNavigationFailure();
  }

  void _showNavigationFailure() {
    final state = ref.read(dreamEditorControllerProvider);
    // 读写失败已有页面内错误和“重试”。额外 Snackbar 会盖住底部重试按钮，
    // 因此让用户直接操作现有错误入口；仅没有具体错误状态时显示一般提示。
    if (state.failure != null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('操作尚未完成，请稍后重试。')));
  }

  @override
  void initState() {
    super.initState();

    // 通知导航可能在页面创建前就加载了当天记录。既处理已加载状态，
    // 也继续在 ref.listen 中处理后续异步加载，避免重建后出现空输入框。
    final current = ref.read(dreamEditorControllerProvider);
    if (!current.isLoading) _textController.text = current.content;

    // Register for events such as the app moving to the background. Mobile
    // operating systems may terminate a background app later, so pending text
    // should be flushed before that can happen.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    super.didChangeAppLifecycleState(lifecycleState);

    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused) {
      final editorState = ref.read(dreamEditorControllerProvider);
      if (editorState.hasPendingSave) {
        // 生命周期回调不能等待 Future 完成，所以这里只能“尽力提交”。
        // 如果旧版本文字正在写入，Controller 会排队保存最新草稿。
        // 系统强杀、断电或进程突然崩溃时，不保证还能执行这个回调；
        // 验收时必须先看到“已保存”，再关闭 App 检查数据库持久化。
        unawaited(ref.read(dreamEditorControllerProvider.notifier).saveNow());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(dreamEditorControllerProvider);

    // Repository reads finish asynchronously. When loading completes, copy the
    // stored content into TextEditingController exactly once. Writing the
    // controller from every build would move the cursor while the user types.
    ref.listen<DreamEditorState>(dreamEditorControllerProvider, (
      previous,
      next,
    ) {
      final loadingJustFinished =
          previous?.isLoading == true && next.isLoading == false;

      if (loadingJustFinished && _textController.text != next.content) {
        _textController.value = TextEditingValue(
          text: next.content,
          selection: TextSelection.collapsed(offset: next.content.length),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('夜行者'),
        centerTitle: false,
        actions: [
          IconButton(
            key: const Key('open-reminders-button'),
            tooltip: '每日提醒',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: _isNavigating || editorState.isLoading
                ? null
                : _openReminders,
          ),
          IconButton(
            key: const Key('select-date-button'),
            tooltip: '选择日期',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _isNavigating || editorState.isLoading
                ? null
                : _chooseDate,
          ),
          IconButton(
            key: const Key('open-history-button'),
            tooltip: '历史梦境',
            icon: const Icon(Icons.history),
            onPressed: _isNavigating || editorState.isLoading
                ? null
                : _openHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: editorState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _EditorBody(
                  state: editorState,
                  textController: _textController,
                  onBackToToday: _isNavigating ? null : _backToToday,
                  onChanged: ref
                      .read(dreamEditorControllerProvider.notifier)
                      .contentChanged,
                  onRetry: () {
                    unawaited(
                      ref
                          .read(dreamEditorControllerProvider.notifier)
                          .retryLastOperation(),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Pure presentation for the loaded editor state.
///
/// Keeping this widget separate makes the top-level page easier to read and
/// makes individual visual states easier to test.
class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.state,
    required this.textController,
    required this.onBackToToday,
    required this.onChanged,
    required this.onRetry,
  });

  final DreamEditorState state;
  final TextEditingController textController;
  final VoidCallback? onBackToToday;
  final ValueChanged<String> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _formatDate(state.date),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (state.date != DreamEntry.dateOnly(DateTime.now()))
              TextButton(
                key: const Key('back-to-today-button'),
                onPressed: onBackToToday,
                child: const Text('回到今天'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          state.date == DreamEntry.dateOnly(DateTime.now())
              ? '趁记忆还清晰，写下你刚刚梦见的内容。'
              : '查看或补记这一天的梦境，修改后仍会自动保存。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TextField(
            key: const Key('dream-content-field'),
            controller: textController,
            // 读取失败时显示错误和重试入口，但不允许把空白界面当作新草稿。
            // 保存失败则继续允许编辑：Controller 会保留并重试最新文字。
            enabled: state.canEdit,
            onChanged: onChanged,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: '梦境记录',
              hintText: '例如：我梦见自己走进了一座没有影子的城市……',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SaveStatusLine(state: state, onRetry: onRetry),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }
}

/// Converts machine-oriented save state into concise user feedback.
class _SaveStatusLine extends StatelessWidget {
  const _SaveStatusLine({required this.state, required this.onRetry});

  final DreamEditorState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state.saveStatus) {
      DreamSaveStatus.idle => (
        Icons.edit_note,
        '尚未修改',
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      DreamSaveStatus.unsaved => (
        Icons.schedule,
        '等待自动保存',
        Theme.of(context).colorScheme.tertiary,
      ),
      DreamSaveStatus.saving => (
        Icons.sync,
        '正在保存',
        Theme.of(context).colorScheme.primary,
      ),
      DreamSaveStatus.saved => (
        Icons.check_circle_outline,
        '已保存',
        Theme.of(context).colorScheme.primary,
      ),
      DreamSaveStatus.failed => (
        Icons.error_outline,
        state.errorMessage ?? '操作失败',
        Theme.of(context).colorScheme.error,
      ),
    };

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            key: const Key('save-status-label'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        if (state.saveStatus == DreamSaveStatus.failed)
          TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
