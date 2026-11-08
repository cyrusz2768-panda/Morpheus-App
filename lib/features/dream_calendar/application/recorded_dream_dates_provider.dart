import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_calendar/data/calendar_repository.dart';
import 'package:morpheus/features/dream_calendar/data/drift_calendar_repository.dart';
import 'package:morpheus/features/dream_editor/data/dream_providers.dart';

/// 月历仓库的装配点。复用编辑器的应用级数据库，不另开一份连接或保存副本。
/// 测试可只替换本接口，月历页面不需要了解 Drift、SQL 或文件路径。
final calendarRepositoryProvider = Provider<ICalendarRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return DriftCalendarRepository(database);
});

/// 一个月对应一个数据库监听；页面应传 DateTime(year, month) 作为稳定参数。
///
/// family 按参数区分月份，autoDispose 会在翻月 / 离开页面后取消旧月份订阅，
/// 数据库仍由应用级 Provider 保持。StreamProvider 提供加载、结果、错误状态；
/// 有效写入提交后日期集合自动更新，不需要编辑器知道月历页面是否正在显示。
final recordedDreamDatesProvider = StreamProvider.autoDispose
    .family<Set<String>, DateTime>(
      (ref, month) {
        final repository = ref.watch(calendarRepositoryProvider);
        return repository.watchRecordedDatesInMonth(month);
      },
      // 查询失败时保留错误与手动重试入口，不在后台反复自动访问数据库。
      retry: (retryCount, error) => null,
    );
