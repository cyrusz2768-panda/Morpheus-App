import 'package:flutter/material.dart';

/// 入口引导使用真正的菜单图标，帮助用户把说明与左上角按钮对应起来。
/// 它只解释入口，不申请系统权限；原来的通知授权说明仍在设置页中展示。
class MenuReminderIntro extends StatelessWidget {
  const MenuReminderIntro({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('menu-reminder-intro'),
      title: const Text('设置每日梦境提醒'),
      content: const Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '点击左上角的 '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.menu, size: 20, semanticLabel: '菜单'),
            ),
            TextSpan(text: ' 按钮，可设置每日记录梦境通知的发送时间。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('dismiss-menu-intro-button'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('知道了'),
        ),
        FilledButton.icon(
          key: const Key('intro-open-menu-button'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.menu),
          label: const Text('打开菜单'),
        ),
      ],
    );
  }
}
