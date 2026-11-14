import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morpheus/features/dream_editor/presentation/widgets/link_text_editing_controller.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('正文链接真实字形点击可打开，空白/长按/拖动仍用于编辑 $platform', (tester) async {
      final controller = LinkTextEditingController(
        text: '文字 example.com\n无效 example..com',
      );
      final opened = <String>[];
      controller.onLinkTap = (link) => opened.add(link.uri.toString());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform, colorSchemeSeed: Colors.purple),
          home: Scaffold(
            body: ContentLinkTapRegion(
              controller: controller,
              builder: (onTap) => TextField(
                controller: controller,
                maxLines: null,
                onTap: onTap,
                onTapAlwaysCalled: true,
              ),
            ),
          ),
        ),
      );
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      Offset glyph(int offset) {
        final box = editable.renderEditable
            .getBoxesForSelection(
              TextSelection(baseOffset: offset, extentOffset: offset + 1),
            )
            .first
            .toRect();
        return editable.renderEditable.localToGlobal(box.center);
      }

      final span = editable.renderEditable.text! as TextSpan;
      final links = span.children!
          .whereType<TextSpan>()
          .where((s) => s.style?.color != null)
          .toList();
      expect(links.single.text, 'example.com');
      expect(
        links.single.style!.color,
        Theme.of(tester.element(find.byType(TextField))).colorScheme.primary,
      );
      expect(span.toPlainText(), controller.text);
      expect(
        span.getSemanticsInformation().every((s) => s.recognizer == null),
        isTrue,
      );
      await tester.tapAt(glyph(4));
      await tester.pump();
      expect(opened, ['https://example.com']);
      opened.clear();
      await tester.tapAt(glyph(0));
      await tester.tapAt(glyph(20));
      await tester.tapAt(glyph(13) + const Offset(100, 0));
      await tester.pump();
      expect(opened, isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.longPressAt(glyph(5));
      await tester.pump();
      expect(opened, isEmpty);
      expect(controller.selection.isValid, isTrue);
      if (platform == TargetPlatform.android) {
        expect(controller.selection.isCollapsed, isFalse);
      }
      final gesture = await tester.startGesture(glyph(5));
      await gesture.moveBy(const Offset(100, 0));
      await gesture.up();
      await tester.pump();
      expect(opened, isEmpty);
      expect(controller.text, '文字 example.com\n无效 example..com');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('高亮不改正文/选区/组合输入，组合区不附加链接手势', (tester) async {
    final controller = LinkTextEditingController();
    const original = TextEditingValue(
      text: '🌙 example.com 和 example.org',
      selection: TextSelection(baseOffset: 3, extentOffset: 14),
      composing: TextRange(start: 3, end: 14),
    );
    controller.value = original;
    controller.onLinkTap = (_) {};
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              withComposing: true,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(controller.value, original);
    expect(span.toPlainText(), original.text);
    final spans = span.children!.cast<TextSpan>();
    expect(
      spans.where((s) => s.style?.color != null).single.text,
      'example.org',
    );
    expect(
      spans
          .where((s) => s.style?.decoration == TextDecoration.underline)
          .single
          .text,
      'example.com',
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
