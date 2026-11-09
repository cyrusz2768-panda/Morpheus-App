import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:morpheus/app/navigation_activity.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/l10n/app_text.dart';

/// 三个顶级页面共用同一底栏，二级页面仍沿用原来的 push/pop，避免改变
/// 历史、搜索和通知弹窗的返回语义。实色胶囊只借鉴参考图的形状与选中态。
class MainBottomNavigation extends ConsumerWidget {
  const MainBottomNavigation({super.key, required this.selectedIndex});
  final int selectedIndex;
  static const _paths = ['/', '/statistics', '/calendar'];

  Future<void> _select(BuildContext context, WidgetRef ref, int index) async {
    if (index == selectedIndex) return;
    final activity = ref.read(navigationActivityProvider.notifier);
    final token = activity.begin();
    if (token == null) return;
    FocusScope.of(context).unfocus();
    try {
      // 即使初次没有草稿，await 也会让出执行权。循环确认输入法在这段
      // 间隙交付的末尾文字，最终检查与 go 在同一同步执行段中完成。
      do {
        final saved = await ref
            .read(dreamEditorControllerProvider.notifier)
            .flushPendingSave();
        if (!context.mounted || !activity.isCurrent(token)) return;
        if (!saved) {
          if (ref.read(dreamEditorControllerProvider).failure == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.navigationIncomplete)),
            );
          }
          return;
        }
      } while (ref.read(dreamEditorControllerProvider).hasPendingSave);
      context.go(_paths[index]);
    } finally {
      activity.end(token);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(navigationActivityProvider);
    final busy =
        ref.read(navigationActivityProvider.notifier).isBusy ||
        ref.watch(
          dreamEditorControllerProvider.select((state) => state.isLoading),
        );
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .5),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: .06),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: NavigationBar(
            selectedIndex: selectedIndex,
            height: 72,
            backgroundColor: Colors.transparent,
            elevation: 0,
            indicatorColor: colors.primaryContainer,
            onDestinationSelected: busy
                ? null
                : (index) => _select(context, ref, index),
            destinations: const [
              NavigationDestination(
                key: Key('nav-record'),
                icon: Icon(Icons.edit_note_outlined),
                selectedIcon: Icon(Icons.edit_note),
                label: '记录',
              ),
              NavigationDestination(
                key: Key('nav-statistics'),
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: '统计',
              ),
              NavigationDestination(
                key: Key('nav-calendar'),
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: '日历',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
