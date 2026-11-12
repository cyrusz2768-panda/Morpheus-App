import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 既有正文/导航回归从“跳过分类”进入原编辑器；新引导行为另有独立测试。
Future<void> openDreamTextIfPrompted(WidgetTester tester) async {
  if (find
      .byKey(const Key('daily-mood-good'))
      .hitTestable()
      .evaluate()
      .isNotEmpty) {
    await tester.tap(find.byKey(const Key('daily-skip')));
    await tester.pumpAndSettle();
  }
}
