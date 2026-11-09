import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:morpheus/app/navigation_activity.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_calendar/presentation/dream_calendar_page.dart';
import 'package:morpheus/features/dream_editor/presentation/dream_editor_page.dart';
import 'package:morpheus/features/dream_history/presentation/dream_history_page.dart';
import 'package:morpheus/features/dream_search/presentation/dream_search_page.dart';
import 'package:morpheus/features/dream_statistics/presentation/dream_statistics_page.dart';
import 'package:morpheus/features/reminders/presentation/reminder_settings_page.dart';
import 'package:morpheus/l10n/app_text.dart';

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
        path: '/search',
        name: 'dream-search',
        builder: (context, state) => const DreamSearchPage(),
      ),
      GoRoute(
        path: '/calendar',
        name: 'dream-calendar',
        builder: (context, state) => _TabBackScope(
          child: Consumer(
            builder: (context, ref, child) => DreamCalendarPage(
              initialDate: ref.read(dreamEditorControllerProvider).date,
              onDateSelected: (date) async {
                final activity = ref.read(navigationActivityProvider.notifier);
                final token = activity.begin();
                if (token == null) return;
                try {
                  final selected = await ref
                      .read(dreamEditorControllerProvider.notifier)
                      .selectDate(date);
                  if (!context.mounted || !activity.isCurrent(token)) return;
                  if (selected) {
                    context.go('/');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.navigationIncomplete),
                      ),
                    );
                  }
                } finally {
                  activity.end(token);
                }
              },
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/statistics',
        name: 'dream-statistics',
        builder: (context, state) =>
            const _TabBackScope(child: DreamStatisticsPage()),
      ),
      GoRoute(
        path: '/calendar-picker',
        name: 'dream-calendar-picker',
        builder: (context, state) {
          final initialDate = state.extra;
          return DreamCalendarPage(
            initialDate: initialDate is DateTime ? initialDate : DateTime.now(),
          );
        },
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

/// Android 的系统返回从两个浏览页回到记录；根记录页保留系统退出行为。
class _TabBackScope extends StatelessWidget {
  const _TabBackScope({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) context.go('/');
    },
    child: child,
  );
}
