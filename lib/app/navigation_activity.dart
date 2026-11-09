import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 顶栏、底栏和选日共用一个导航锁。令牌用于等待异步保存后确认意图
/// 仍有效：通知返回今天会撤销旧意图，避免旧 Future 随后又跳回统计页。
final navigationActivityProvider = NotifierProvider<NavigationActivity, int>(
  NavigationActivity.new,
);

class NavigationActivity extends Notifier<int> {
  int? _active;
  @override
  int build() => 0;
  bool get isBusy => _active != null;
  int? begin() {
    if (isBusy) return null;
    final token = state + 1;
    _active = token;
    state = token;
    return token;
  }

  bool isCurrent(int token) => ref.mounted && _active == token;
  void end(int token) {
    if (isCurrent(token)) cancel();
  }

  void cancel() {
    _active = null;
    state += 1;
  }
}
