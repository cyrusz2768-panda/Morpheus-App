import 'package:flutter/material.dart';

/// 左侧抽屉只展示菜单；保存草稿和导航仍由编辑页协调。
/// Drawer 自带从左侧进入、点击遮罩关闭和返回手势，不必自行实现动画。
class EditorMenuDrawer extends StatelessWidget {
  const EditorMenuDrawer({
    super.key,
    required this.canNavigate,
    required this.onOpenReminders,
    required this.onClose,
  });

  final bool canNavigate;
  final VoidCallback onOpenReminders;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      key: const Key('main-menu-drawer'),
      // 按手机屏幕比例占据大部分宽度，右侧保留遮罩，便于点击收起。
      width: MediaQuery.sizeOf(context).width * 0.82,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '夜行者',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭菜单',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('open-reminders-menu-item'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('通知设置'),
              onTap: canNavigate ? onOpenReminders : null,
            ),
          ],
        ),
      ),
    );
  }
}
