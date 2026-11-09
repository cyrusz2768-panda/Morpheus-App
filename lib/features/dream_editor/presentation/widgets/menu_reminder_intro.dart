import 'package:flutter/material.dart';
import 'package:morpheus/l10n/app_text.dart';

/// 入口引导使用真正的菜单图标，帮助用户把说明与左上角按钮对应起来。
/// 它只解释入口，不申请系统权限；原来的通知授权说明仍在设置页中展示。
class MenuReminderIntro extends StatelessWidget {
  const MenuReminderIntro({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('menu-reminder-intro'),
      title: Text(context.l10n.menuIntroTitle),
      content: Text.rich(TextSpan(children: _introSpans(context))),
      actions: [
        TextButton(
          key: const Key('dismiss-menu-intro-button'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.gotIt),
        ),
        FilledButton.icon(
          key: const Key('intro-open-menu-button'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.menu),
          label: Text(context.l10n.openMenu),
        ),
      ],
    );
  }

  List<InlineSpan> _introSpans(BuildContext context) {
    // 用不可见的对象占位符定位图标，让翻译保留完整句子并自由调整图标位置。
    // split 仅作用于资源消息，绝不处理用户正文；前后空格由 ARB 自己控制。
    const marker = '\uFFFC';
    final parts = context.l10n.menuIntroBody(marker).split(marker);
    return [
      for (var index = 0; index < parts.length; index++) ...[
        if (index > 0)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.menu, size: 20, semanticLabel: context.l10n.menu),
          ),
        TextSpan(text: parts[index]),
      ],
    ];
  }
}
