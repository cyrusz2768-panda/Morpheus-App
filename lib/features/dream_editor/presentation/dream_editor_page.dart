import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_state.dart';

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

  @override
  void initState() {
    super.initState();

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
    final editorState = ref.watch(dreamEditorControllerProvider);

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
      appBar: AppBar(title: const Text('夜行者'), centerTitle: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: editorState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : _EditorBody(
                  state: editorState,
                  textController: _textController,
                  onChanged: ref
                      .read(dreamEditorControllerProvider.notifier)
                      .contentChanged,
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
    required this.textController,
    required this.onChanged,
    required this.onRetry,
  });

  final DreamEditorState state;
  final TextEditingController textController;
  final ValueChanged<String> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _formatDate(state.date),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '趁记忆还清晰，写下你刚刚梦见的内容。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TextField(
            key: const Key('dream-content-field'),
            controller: textController,
            // 读取失败时显示错误和重试入口，但不允许把空白界面当作新草稿。
            // 保存失败则继续允许编辑：Controller 会保留并重试最新文字。
            enabled: state.canEdit,
            onChanged: onChanged,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: '梦境记录',
              hintText: '例如：我梦见自己走进了一座没有影子的城市……',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SaveStatusLine(state: state, onRetry: onRetry),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
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
        '尚未修改',
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      DreamSaveStatus.unsaved => (
        Icons.schedule,
        '等待自动保存',
        Theme.of(context).colorScheme.tertiary,
      ),
      DreamSaveStatus.saving => (
        Icons.sync,
        '正在保存',
        Theme.of(context).colorScheme.primary,
      ),
      DreamSaveStatus.saved => (
        Icons.check_circle_outline,
        '已保存',
        Theme.of(context).colorScheme.primary,
      ),
      DreamSaveStatus.failed => (
        Icons.error_outline,
        state.errorMessage ?? '操作失败',
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
          TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
