import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/core/db/app_database.dart';
import 'package:morpheus/features/dream_editor/data/dream_repository.dart';
import 'package:morpheus/features/dream_editor/data/drift_dream_repository.dart';

/// 整个 ProviderScope 共用一条数据库连接，而不是每次输入都重新打开文件。
///
/// 这里不使用 autoDispose，避免一次页面切换就提前关闭还在使用的数据库。
/// 测试或整个容器被销毁时释放连接；正常写入已经在 save 的 Future 中提交，
/// 并不是等到 close() 时才保存。系统直接终止 App 时也不会等待这个回调。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

/// 唯一的存储装配点：正式 App 使用 Drift，测试仍可替换为内存 / 故障仓库。
/// Controller 不必知道文件路径、SQL 或 Android / iOS 平台细节。
final dreamRepositoryProvider = Provider<DreamRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return DriftDreamRepository(database);
});
