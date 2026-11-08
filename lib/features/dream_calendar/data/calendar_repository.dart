/// 月历只需要知道“哪些日期有正文”，无需读取整份历史或正文列表。
///
/// 将这个只读投影独立成接口，编辑器继续通过原有 DreamRepository 写入；
/// 页面测试可以注入确定的日期流，而不必依赖 SQLite 或真实用户数据。
abstract interface class ICalendarRepository {
  /// 监听 [month] 所在月份有有效正文的日期，日期键格式为 yyyy-mm-dd。
  ///
  /// 只使用参数的年、月，忽略日期和时刻，不把日历月份转换为 UTC 月份。
  /// 首次订阅会返回当前快照；相关记录保存、修改或删除后继续发出新快照。
  /// 无记录时返回空集合；读取失败沿流向上传递，不能把失败显示成“没有记录”。
  Stream<Set<String>> watchRecordedDatesInMonth(DateTime month);
}
