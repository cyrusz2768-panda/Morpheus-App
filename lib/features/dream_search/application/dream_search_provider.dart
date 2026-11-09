import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';
import 'package:morpheus/features/dream_search/data/dream_search_repository.dart';
import 'package:morpheus/features/dream_search/data/drift_dream_search_repository.dart';

/// 搜索与编辑器共享数据库；测试可以单独替换只读接口，不接触用户数据。
final dreamSearchRepositoryProvider = Provider<IDreamSearchRepository>((ref) {
  return DriftDreamSearchRepository(ref.watch(appDatabaseProvider));
});

/// 每个已确认的关键词对应独立查询，连续输入停顿 300ms 后才访问数据库。
///
/// 页面只监听当前关键词。换词或退出后 autoDispose 释放旧状态；延迟结束时
/// 检查 mounted，避免已失效的词仍发起 SQL。已经开始的查询可以完成，但其
/// Future 属于旧 Provider，不能覆盖新词的结果，也不会写入数据库。
final dreamSearchProvider = FutureProvider.autoDispose
    .family<List<DreamEntry>, String>((ref, keyword) async {
      final term = keyword.trim();
      if (term.isEmpty) return const [];
      final repository = ref.watch(dreamSearchRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!ref.mounted) return const [];
      return repository.search(term);
    }, retry: (retryCount, error) => null);
