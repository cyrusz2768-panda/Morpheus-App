import 'package:morpheus/features/dream_editor/presentation/widgets/daily_record_flow.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:morpheus/app/main_bottom_navigation.dart';
import 'package:morpheus/app/navigation_activity.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_editor/presentation/widgets/editor_menu_drawer.dart';
import 'package:morpheus/features/dream_editor/presentation/widgets/menu_reminder_intro.dart';
import 'package:morpheus/features/dream_history/application/dream_history_provider.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/l10n/app_text.dart';

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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _menuHintQueued = false;
  bool _menuHintShown = false;

  // 一次只处理一个页面/日期导航操作，防止快速连点弹出多个页面或并发切日。
  // 这是页面交互状态；正文、保存结果与所选日期仍由 Controller 管理。
  bool _isNavigating = false;

  void _openMenu() {
    if (_isNavigating || ref.read(dreamEditorControllerProvider).isLoading) {
      return;
    }
    FocusScope.of(context).unfocus();
    _scaffoldKey.currentState?.openDrawer();
  }

  void _openRemindersFromMenu() {
    // closeDrawer 只关闭抽屉，不会误把编辑器路由 pop 掉。设置导航继续沿用
    // 原有的保存等待和失败保护，避免搬动入口时改变正文的保存行为。
    _scaffoldKey.currentState?.closeDrawer();
    unawaited(_openReminders());
  }

  bool _canShowMenuHint(ReminderState reminder) {
    return !_menuHintShown &&
        !_isNavigating &&
        !ref.read(navigationActivityProvider.notifier).isBusy &&
        !ref.read(dreamEditorControllerProvider).isLoading &&
        !reminder.isLoading &&
        !reminder.isBusy &&
        reminder.settings != null &&
        !reminder.settings!.menuHintSeen &&
        ModalRoute.of(context)?.isCurrent == true &&
        _scaffoldKey.currentState?.isDrawerOpen != true;
  }

  void _queueMenuHint(ReminderState reminder) {
    if (_menuHintQueued || !_canShowMenuHint(reminder)) return;
    _menuHintQueued = true;
    // 不能在 build 中直接弹窗。等本帧完成后再次检查当前路由，防止加载
    // 期间用户已经进入月历，提示却又盖到另一个页面上。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _menuHintQueued = false;
      if (!mounted || !_canShowMenuHint(ref.read(reminderControllerProvider))) {
        return;
      }
      _menuHintShown = true;
      unawaited(_showMenuHint());
    });
  }

  Future<void> _showMenuHint() async {
    final openMenu = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MenuReminderIntro(),
    );
    if (!mounted) return;
    // 入口提示与“是否读过系统通知授权说明”是两个独立状态，不能互相覆盖。
    // 本次会话已经显示过，即使磁盘写入失败，也不反复弹窗打断用户记录。
    await ref.read(reminderControllerProvider.notifier).acknowledgeMenuHint();
    if (mounted && openMenu == true) _openMenu();
  }

  Future<void> _openReminders() async {
    if (_isNavigating) return;
    final activity = ref.read(navigationActivityProvider.notifier);
    final token = activity.begin();
    if (token == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      // 与打开历史一样，离开编辑页前等待最新草稿。权限弹窗可能让 App
      // 进入 inactive 状态，所以先确保正文已经保存，再处理提醒设置。
      do {
        final saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!mounted || !activity.isCurrent(token)) return;
        if (!saved) {
          _showNavigationFailure();
          return;
        }
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      await context.push<void>('/reminders');
    } finally {
      activity.end(token);
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _chooseDate() async {
    if (_isNavigating) return;
    final activity = ref.read(navigationActivityProvider.notifier);
    final token = activity.begin();
    if (token == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      // 月历的圆点来自已写入数据库的记录。先保存最新草稿，再打开月历，
      // 刚新增/清空的日期才会立即出现/移除标记；失败时留在编辑器重试。
      do {
        final saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!mounted || !activity.isCurrent(token)) return;
        if (!saved) {
          _showNavigationFailure();
          return;
        }
        // await 期间输入法可能交付末尾文字，导航前同步确认一次。
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      final chosen = await context.push<DateTime>(
        '/calendar-picker',
        extra: ref.read(dreamEditorControllerProvider).date,
      );
      if (mounted && activity.isCurrent(token) && chosen != null) {
        await _applyDate(chosen);
      }
    } finally {
      activity.end(token);
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _openHistory() async {
    if (_isNavigating) return;
    final activity = ref.read(navigationActivityProvider.notifier);
    final token = activity.begin();
    if (token == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      // 等待真正写入后再进入列表，避免用户刚输入的梦境还没出现在历史中。
      do {
        final saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!mounted || !activity.isCurrent(token)) return;
        if (!saved) {
          _showNavigationFailure();
          return;
        }
        // await 让出执行权期间，输入法可能刚好提交最后一段文字。导航前再
        // 确认一次；这个最终检查与 push 之间没有 await，不留未提交窗口。
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      ref.invalidate(dreamHistoryProvider);
      final date = await context.push<DateTime>('/history');
      if (mounted && activity.isCurrent(token) && date != null) {
        await _applyDate(date);
      }
    } finally {
      activity.end(token);
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _backToToday() async {
    if (_isNavigating) return;
    final activity = ref.read(navigationActivityProvider.notifier);
    final token = activity.begin();
    if (token == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      await _applyDate(DreamEntry.dateOnly(DateTime.now()));
    } finally {
      activity.end(token);
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _openSearch() async {
    if (_isNavigating) return;
    final activity = ref.read(navigationActivityProvider.notifier);
    final token = activity.begin();
    if (token == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _isNavigating = true);
    try {
      // 搜索只查已落盘正文，必须先提交当前草稿。await 间隙输入法还可能
      // 交付末尾文字，因此循环确认最新草稿；失败时留在原页保留输入。
      do {
        final saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!mounted || !activity.isCurrent(token)) return;
        if (!saved) {
          _showNavigationFailure();
          return;
        }
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      final date = await context.push<DateTime>('/search');
      if (mounted && activity.isCurrent(token) && date != null) {
        await _applyDate(date);
      }
    } finally {
      activity.end(token);
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
    ).showSnackBar(SnackBar(content: Text(context.l10n.navigationIncomplete)));
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
    ref.watch(navigationActivityProvider);
    final navigationBusy =
        _isNavigating ||
        ref.read(navigationActivityProvider.notifier).isBusy ||
        (ref.watch(dreamEditorControllerProvider).isAdvancing ||
            ref.watch(dreamEditorControllerProvider).isAddingImages);
    final editorState = ref.watch(dreamEditorControllerProvider);
    final reminderState = ref.watch(reminderControllerProvider);
    _queueMenuHint(reminderState);

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
      key: _scaffoldKey,
      bottomNavigationBar: const MainBottomNavigation(selectedIndex: 0),
      drawer: EditorMenuDrawer(
        canNavigate: !navigationBusy && !editorState.isLoading,
        onOpenReminders: _openRemindersFromMenu,
        onClose: () => _scaffoldKey.currentState?.closeDrawer(),
      ),
      onDrawerChanged: (isOpen) {
        // 若配置恰好在抽屉打开期间读完，等抽屉关闭后再考虑首次提示。
        if (!isOpen && mounted) setState(() {});
      },
      appBar: AppBar(
        leading: IconButton(
          key: const Key('open-menu-button'),
          tooltip: context.l10n.openMenu,
          icon: const Icon(Icons.menu),
          onPressed: navigationBusy || editorState.isLoading ? null : _openMenu,
        ),
        title: Text(context.l10n.appTitle),
        centerTitle: false,
        actions: [
          IconButton(
            key: const Key('open-search-button'),
            tooltip: context.l10n.searchDreams,
            icon: const Icon(Icons.search),
            onPressed: navigationBusy || editorState.isLoading
                ? null
                : _openSearch,
          ),
          IconButton(
            key: const Key('select-date-button'),
            tooltip: context.l10n.selectDate,
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: navigationBusy || editorState.isLoading
                ? null
                : _chooseDate,
          ),
          IconButton(
            key: const Key('open-history-button'),
            tooltip: context.l10n.dreamHistory,
            icon: const Icon(Icons.history),
            onPressed: navigationBusy || editorState.isLoading
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
                  controller: ref.read(dreamEditorControllerProvider.notifier),
                  navigationBusy: navigationBusy,
                  textController: _textController,
                  onBackToToday: navigationBusy ? null : _backToToday,
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
    required this.controller,
    required this.navigationBusy,
    required this.textController,
    required this.onBackToToday,
    required this.onRetry,
  });

  final DreamEditorState state;
  final DreamEditorController controller;
  final bool navigationBusy;
  final TextEditingController textController;
  final VoidCallback? onBackToToday;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // 正文页的保存状态也参与文档排版，图片增高时不能仍悬在图片前面。
    // 分类/评分等其他步骤维持既有的固定保存提示，不扩大此次 UI 调整范围。
    final statusFollowsContent =
        state.step == DailyRecordStep.content || !state.canEdit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.dreamDate(
                  state.date.year,
                  state.date.month,
                  state.date.day,
                ),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (state.date != DreamEntry.dateOnly(DateTime.now()))
              TextButton(
                key: const Key('back-to-today-button'),
                onPressed: onBackToToday,
                child: Text(context.l10n.backToToday),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          state.date == DreamEntry.dateOnly(DateTime.now())
              ? context.l10n.editorTodayPrompt
              : context.l10n.editorPastPrompt,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: DailyRecordFlow(
            state: state,
            controller: controller,
            textController: textController,
            navigationBusy: navigationBusy,
            contentFooter: statusFollowsContent
                ? _SaveStatusLine(state: state, onRetry: onRetry)
                : null,
          ),
        ),
        if (!statusFollowsContent) ...[
          const SizedBox(height: 12),
          _SaveStatusLine(state: state, onRetry: onRetry),
        ],
      ],
    );
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
        context.l10n.saveIdle,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      DreamSaveStatus.unsaved => (
        Icons.schedule,
        context.l10n.savePending,
        Theme.of(context).colorScheme.tertiary,
      ),
      DreamSaveStatus.saving => (
        Icons.sync,
        context.l10n.saveInProgress,
        Theme.of(context).colorScheme.primary,
      ),
      DreamSaveStatus.saved => (
        Icons.check_circle_outline,
        context.l10n.saveComplete,
        Theme.of(context).colorScheme.primary,
      ),
      DreamSaveStatus.failed => (
        Icons.error_outline,
        state.errorMessage ?? context.l10n.operationFailed,
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
          TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    );
  }
}
