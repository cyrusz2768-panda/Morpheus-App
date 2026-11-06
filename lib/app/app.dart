import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:morpheus/app/router.dart';
import 'package:morpheus/app/theme.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';
import 'package:morpheus/features/reminders/application/reminder_controller.dart';

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
          const SnackBar(content: Text('暂时无法打开当天记录，请先重试保存当前草稿。')),
        );
      }
    } finally {
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
      title: '夜行者',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 当前练习项目以中文为默认语言。SDK 的 delegate 负责日期选择器等
      // 标准组件的本地化，避免出现页面中文、月份和星期却为英文的混用。
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
    );
  }
}
