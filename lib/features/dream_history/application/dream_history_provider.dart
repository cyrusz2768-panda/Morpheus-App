import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';
import 'package:morpheus/features/dream_editor/domain/dream_entry.dart';

/// 历史页的异步数据入口，不在 Widget 中直接编写 SQL。
///
/// FutureProvider 会把一次查询转换成加载中、成功或失败三种 UI 状态。
/// autoDispose 让离开历史页后释放查询结果；数据库连接仍由应用级 Provider
/// 管理，不会随列表页面关闭。每次打开历史前及点击刷新/重试都会重新查询，
/// 因此刚保存、修改或删除的内容不会被旧列表缓存遮住。
final dreamHistoryProvider = FutureProvider.autoDispose<List<DreamEntry>>(
  (ref) {
    final repository = ref.watch(dreamRepositoryProvider);
    return repository.getAll();
  },
  // 错误时保留明确的重试入口，由用户点击重试；不在后台反复自动查询。
  retry: (retryCount, error) => null,
);
