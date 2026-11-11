import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/app/router.dart';
import 'package:morpheus/app/navigation_activity.dart';
import 'package:morpheus/app/theme.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
import 'package:morpheus/features/reminders/data/reminder_notifications.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/l10n/app_text.dart';

/// The root widget of the application.
///
/// This widget owns application-wide concerns: routing, theme and the title
/// shown by the operating system. Feature-specific behavior does not belong
/// here; for example, saving a dream is handled by DreamEditorController.
class MorpheusApp extends ConsumerStatefulWidget {
  const MorpheusApp({super.key});

  @override
  ConsumerState<MorpheusApp> createState() => _MorpheusAppState();
}

class _MorpheusAppState extends ConsumerState<MorpheusApp>
    with WidgetsBindingObserver {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  // 点击时捕获日期，而非等待保存后再取时间；跨午夜写入不应改变用户目标。
  // 可空请求替代布尔标记，让每日记录与每周统计走同一套草稿保护。
  ({ReminderDestination destination, DateTime anchor, int sequence})?
  _pendingNotification;
  bool _handlingNotification = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统权限设置返回时重新查询；不把上次的权限状态当成永久事实。
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(reminderControllerProvider.notifier).load());
    }
  }

  void _queueNotificationNavigation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openFromNotification());
    });
    // 通知可能在完全静止的页面到达；只注册帧后回调不会自行产生新一帧。
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openFromNotification() async {
    if (_pendingNotification == null || _handlingNotification || !mounted) {
      return;
    }
    // 冷启动时数据库可能还在加载，保留意图，等待下面的状态监听再次处理。
    if (ref.read(dreamEditorControllerProvider).isLoading) return;
    _handlingNotification = true;
    final activity = ref.read(navigationActivityProvider.notifier);
    activity.cancel();
    final navigationToken = activity.begin()!;
    final request = _pendingNotification!;
    _pendingNotification = null;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      bool saved;
      do {
        saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!mounted || !saved) break;
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      if (!mounted) return;
      // 等待中有更新的点击时，旧目标不再导航，由 finally 排队消费最新目标。
      if (_pendingNotification != null) return;
      final weekly =
          request.destination == ReminderDestination.weeklyStatistics;
      final selected =
          saved &&
          (weekly ||
              await ref
                  .read(dreamEditorControllerProvider.notifier)
                  .selectDate(request.anchor));
      if (!mounted || _pendingNotification != null) return;
      if (selected) {
        final router = ref.read(appRouterProvider);
        // 先关闭时间/日期弹窗和设置页，再进入目标页，避免旧弹窗遮住目标。
        while (router.canPop()) {
          router.pop();
        }
        router.go(
          weekly
              ? '/statistics?week=${DreamEntry.dateKey(request.anchor)}&request=${request.sequence}'
              : '/',
        );
      } else if (ref.read(dreamEditorControllerProvider).failure == null) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              weekly
                  ? ref.read(appLocalizationsProvider).weeklyNavigationFailed
                  : ref
                        .read(appLocalizationsProvider)
                        .notificationNavigationFailed,
            ),
          ),
        );
      }
    } finally {
      activity.end(navigationToken);
      _handlingNotification = false;
      if (_pendingNotification != null && mounted) {
        _queueNotificationNavigation();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reading the router through a provider makes it disposable and replaceable
    // in tests. `watch` rebuilds this widget if the provider ever changes.
    final router = ref.watch(appRouterProvider);
    // 监听本身也会启动提醒服务。初始化不弹系统权限，不阻塞梦境页面。
    ref.listen<ReminderState>(reminderControllerProvider, (previous, next) {
      if (next.tapSequence != (previous?.tapSequence ?? 0)) {
        _pendingNotification = (
          destination: next.destination,
          anchor: DateTime.now(),
          sequence: next.tapSequence,
        );
        _queueNotificationNavigation();
      }
    });
    ref.listen<DreamEditorState>(dreamEditorControllerProvider, (
      previous,
      next,
    ) {
      if (!next.isLoading && _pendingNotification != null) {
        _queueNotificationNavigation();
      }
    });

    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 应用文案与标准组件共用同一套语言配置；当前只交付中文资源。
      locale: morpheusLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
    );
  }
}
