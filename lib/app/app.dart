import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/app/router.dart';
import 'package:morpheus/app/navigation_activity.dart';
import 'package:morpheus/app/theme.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';
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
  bool _pendingNotification = false;
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
      if (mounted) unawaited(_openTodayFromNotification());
    });
    // 通知可能在完全静止的页面到达；只注册帧后回调不会自行产生新一帧。
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openTodayFromNotification() async {
    if (!_pendingNotification || _handlingNotification || !mounted) return;
    // 冷启动时数据库可能还在加载，保留意图，等待下面的状态监听再次处理。
    if (ref.read(dreamEditorControllerProvider).isLoading) return;
    _handlingNotification = true;
    final activity = ref.read(navigationActivityProvider.notifier);
    activity.cancel();
    final navigationToken = activity.begin()!;
    _pendingNotification = false;
    try {
      bool saved;
      do {
        saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!mounted || !saved) break;
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      if (!mounted) return;
      final selected =
          saved &&
          await ref
              .read(dreamEditorControllerProvider.notifier)
              .selectDate(DateTime.now());
      if (!mounted) return;
      if (selected) {
        final router = ref.read(appRouterProvider);
        // 先关闭时间/日期弹窗和设置页，再回到编辑器，避免旧弹窗盖在当天上。
        while (router.canPop()) {
          router.pop();
        }
        router.go('/');
      } else if (ref.read(dreamEditorControllerProvider).failure == null) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              ref.read(appLocalizationsProvider).notificationNavigationFailed,
            ),
          ),
        );
      }
    } finally {
      activity.end(navigationToken);
      _handlingNotification = false;
      if (_pendingNotification && mounted) _queueNotificationNavigation();
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
        _pendingNotification = true;
        _queueNotificationNavigation();
      }
    });
    ref.listen<DreamEditorState>(dreamEditorControllerProvider, (
      previous,
      next,
    ) {
      if (!next.isLoading && _pendingNotification) {
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
