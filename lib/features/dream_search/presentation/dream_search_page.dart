import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_search/application/dream_search_provider.dart';
import 'package:morpheus/l10n/app_text.dart';

/// 搜索页只管理输入与展示，查询交给 Provider / Repository，选中后只返回日期。
/// 编辑、保存及失败保护继续复用原编辑器，避免产生第二套正文写入逻辑。
class DreamSearchPage extends ConsumerStatefulWidget {
  const DreamSearchPage({super.key});

  @override
  ConsumerState<DreamSearchPage> createState() => _DreamSearchPageState();
}

class _DreamSearchPageState extends ConsumerState<DreamSearchPage> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  String _keyword = '';
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    // 监听完整 TextEditingValue，才能分辨中文输入法尚未确认的拼音和正式文字。
    // 只用 onChanged 会漏掉“文字不变、composing 区间结束”的确认事件。
    _textController.addListener(_inputChanged);
  }

  void _inputChanged() {
    final value = _textController.value;
    setState(() {
      _keyword = value.text.trim();
      _isComposing = value.composing.isValid && !value.composing.isCollapsed;
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_inputChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 空输入和输入法组词期间不订阅查询，也不展示上一个词的陈旧结果。
    final results = _keyword.isNotEmpty && !_isComposing
        ? ref.watch(dreamSearchProvider(_keyword))
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.searchDreams)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: TextField(
                key: const Key('dream-search-field'),
                controller: _textController,
                focusNode: _focusNode,
                // 路由展示后由 Flutter 请求焦点，两端共用系统输入法；页面重建
                // 不反复抢焦点，返回时 FocusNode 也随页面释放。
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _focusNode.unfocus(),
                decoration: InputDecoration(
                  hintText: context.l10n.searchContentHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _textController.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('clear-dream-search'),
                          tooltip: context.l10n.clearSearch,
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _textController.clear();
                            _focusNode.requestFocus();
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: results == null
                  ? _SearchMessage(
                      text: _isComposing
                          ? context.l10n.searchComposing
                          : context.l10n.searchPrompt,
                    )
                  : results.when(
                      // 切词/重试时隐藏旧列表，不能把旧词的结果当作新词的结果。
                      skipLoadingOnReload: false,
                      skipLoadingOnRefresh: false,
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stackTrace) => _SearchMessage(
                        text: context.l10n.searchFailed,
                        onRetry: () =>
                            ref.invalidate(dreamSearchProvider(_keyword)),
                      ),
                      data: (entries) => entries.isEmpty
                          ? _SearchMessage(text: context.l10n.searchNoResults)
                          : ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: entries.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final entry = entries[index];
                                final date = entry.dreamDate;
                                return ListTile(
                                  key: Key(
                                    'search-entry-${DreamEntry.dateKey(date)}',
                                  ),
                                  leading: const Icon(
                                    Icons.description_outlined,
                                  ),
                                  title: Text(
                                    context.l10n.dreamDate(
                                      date.year,
                                      date.month,
                                      date.day,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _preview(entry.content, _keyword),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    _focusNode.unfocus();
                                    context.pop<DateTime>(date);
                                  },
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 从首个命中位置附近截取预览，长正文的关键词也能出现在列表中。
  /// 正则只用于展示，escape 防止标点变成语法；unicode 避免截断 emoji，
  /// dotAll 允许关键词跨换行匹配。原文不修改，点开仍读取完整正文。
  String _preview(String content, String keyword) {
    final match = RegExp(
      '.{0,24}${RegExp.escape(keyword)}.{0,90}',
      caseSensitive: false,
      unicode: true,
      dotAll: true,
    ).firstMatch(content);
    if (match == null) return content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final excerpt = match.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${match.start > 0 ? '…' : ''}$excerpt${match.end < content.length ? '…' : ''}';
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    );
  }
}
