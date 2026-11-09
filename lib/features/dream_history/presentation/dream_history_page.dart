import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_history/application/dream_history_provider.dart';
import 'package:morpheus/l10n/app_text.dart';

/// 按梦境所属日期倒序回顾已保存记录，沿用现有 Material 主题。
///
/// 列表只显示正文预览；点击记录后把“日期”交还编辑器，完整正文仍通过
/// Repository 按日期读取。这样查看、修改、删除都复用原来的可靠保存链路。
class DreamHistoryPage extends ConsumerWidget {
  const DreamHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(dreamHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.dreamHistory),
        actions: [
          IconButton(
            tooltip: context.l10n.refreshHistory,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(dreamHistoryProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.historyLoadFailed),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(dreamHistoryProvider),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_stories_outlined, size: 40),
                      const SizedBox(height: 12),
                      Text(context.l10n.noDreamRecords),
                      const SizedBox(height: 8),
                      Text(context.l10n.historyEmptyPrompt),
                    ],
                  ),
                ),
              );
            }

            // builder 按需创建可见的行。预览的空白压缩仅用于显示，不会改写
            // 数据库中的原文；选择后打开编辑器仍可看到原始换行和空格。
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final date = entry.dreamDate;
                return ListTile(
                  key: Key('history-entry-${DreamEntry.dateKey(date)}'),
                  leading: const Icon(Icons.description_outlined),
                  title: Text(
                    context.l10n.dreamDate(date.year, date.month, date.day),
                  ),
                  subtitle: Text(
                    entry.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pop<DateTime>(date),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
