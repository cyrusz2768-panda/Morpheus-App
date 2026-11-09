import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';
import 'package:morpheus/features/dream_statistics/data/drift_statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/data/statistics_repository.dart';
import 'package:morpheus/features/dream_statistics/domain/dream_statistics.dart';

final statisticsRepositoryProvider = Provider<IStatisticsRepository>(
  (ref) => DriftStatisticsRepository(ref.watch(appDatabaseProvider)),
);

/// family 用值相等的窗口复用订阅；翻期/离开后自动释放，不积累多年监听。
/// 不自动重试读取故障，让用户明确看到未知状态并可手动重试。
final statisticsDatesProvider = StreamProvider.autoDispose
    .family<Set<String>, StatisticsWindow>(
      (ref, window) =>
          ref.watch(statisticsRepositoryProvider).watchRecordedDates(window),
      retry: (retryCount, error) => null,
    );
