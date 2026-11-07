import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:morpheus/features/dream_editor/presentation/dream_editor_page.dart';
import 'package:morpheus/features/dream_history/presentation/dream_history_page.dart';
import 'package:morpheus/features/reminders/presentation/reminder_settings_page.dart';

/// Central navigation configuration.
///
/// 编辑器与历史页共用同一个 ProviderScope 和数据库连接。
/// 历史页只返回所选日期，编辑器负责安全保存当前草稿后再读取对应记录。
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'dream-editor',
        builder: (context, state) => const DreamEditorPage(),
      ),
      GoRoute(
        path: '/history',
        name: 'dream-history',
        builder: (context, state) => const DreamHistoryPage(),
      ),
      GoRoute(
        path: '/reminders',
        name: 'reminder-settings',
        builder: (context, state) => const ReminderSettingsPage(),
      ),
    ],
  );

  // GoRouter owns streams and listeners. Disposing it with the provider avoids
  // resource leaks during hot restart and automated tests.
  ref.onDispose(router.dispose);
  return router;
});
