import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:morpheus/features/dream_editor/domain/content_web_link.dart';

/// 只定制正文的绘制和点击，不格式化或替换TextEditingValue，保留输入法、选区和原文。
/// 可编辑文本的语义树不支持带recognizer的Span，点击由下方区域交给TextField自身识别。
class LinkTextEditingController extends TextEditingController {
  LinkTextEditingController({super.text});
  ValueChanged<ContentWebLink>? onLinkTap;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final composing =
        withComposing &&
            value.isComposingRangeValid &&
            !value.composing.isCollapsed
        ? value.composing
        : TextRange.empty;
    // 组合输入尚未确认时只保留输入法下划线，不抢正在编辑的网址片段的手势。
    final links = ContentWebLinks.find(text)
        .where(
          (link) =>
              !composing.isValid ||
              link.end <= composing.start ||
              link.start >= composing.end,
        )
        .toList();
    final spans = <InlineSpan>[];
    var cursor = 0;
    void plain(int start, int end) {
      if (start >= end) return;
      if (!composing.isValid ||
          end <= composing.start ||
          start >= composing.end) {
        spans.add(TextSpan(text: text.substring(start, end)));
      } else {
        if (start < composing.start) {
          spans.add(TextSpan(text: text.substring(start, composing.start)));
        }
        final from = start > composing.start ? start : composing.start;
        final to = end < composing.end ? end : composing.end;
        spans.add(
          TextSpan(
            text: text.substring(from, to),
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
        if (end > composing.end) {
          spans.add(TextSpan(text: text.substring(composing.end, end)));
        }
      }
    }

    for (final link in links) {
      plain(cursor, link.start);
      spans.add(
        TextSpan(
          text: link.text,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      );
      cursor = link.end;
    }
    plain(cursor, text.length);
    return TextSpan(style: style, children: spans);
  }

  @override
  void dispose() {
    onLinkTap = null;
    super.dispose();
  }
}

/// Listener只记录落点，不参加手势竞争；短按由TextField.onTap判定，
/// 因此长按选字、拖动光标和页面滚动仍由Flutter原来的手势逻辑处理。
class ContentLinkTapRegion extends StatefulWidget {
  const ContentLinkTapRegion({
    super.key,
    required this.controller,
    required this.builder,
  });
  final TextEditingController controller;
  final Widget Function(VoidCallback onTap) builder;

  @override
  State<ContentLinkTapRegion> createState() => _ContentLinkTapRegionState();
}

class _ContentLinkTapRegionState extends State<ContentLinkTapRegion> {
  ContentWebLink? _pressed;
  String? _pressedText;
  Offset? _downPosition;
  Timer? _expiry;
  final Set<int> _pointers = {};

  RenderEditable? _findEditable(RenderObject? object) {
    if (object is RenderEditable) return object;
    RenderEditable? result;
    object?.visitChildren((child) => result ??= _findEditable(child));
    return result;
  }

  void _pointerDown(PointerDownEvent event) {
    _expiry?.cancel();
    _pressed = null;
    final wasEmpty = _pointers.isEmpty;
    _pointers.add(event.pointer);
    if (!wasEmpty || event.buttons != kPrimaryButton) return;
    final controller = widget.controller;
    if (controller is! LinkTextEditingController ||
        controller.onLinkTap == null) {
      return;
    }
    _downPosition = event.position;
    _pressedText = widget.controller.text;
    final editable = _findEditable(context.findRenderObject());
    if (editable == null) return;
    final position = editable.getPositionForPoint(event.position).offset;
    final local = editable.globalToLocal(event.position);
    final value = widget.controller.value;
    for (final link in ContentWebLinks.find(_pressedText!)) {
      if (value.isComposingRangeValid &&
          !value.composing.isCollapsed &&
          link.start < value.composing.end &&
          link.end > value.composing.start) {
        continue;
      }
      // 插入点可能落在最后一个字形的右侧，范围用闭区间；再用字形盒排除行尾空白。
      if (position < link.start || position > link.end) continue;
      final boxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: link.start, extentOffset: link.end),
      );
      if (boxes.any((box) => box.toRect().contains(local))) {
        _pressed = link;
        break;
      }
    }
    // 连续点击后的按住也可能收到TextField.onTap；明确排除长按，避免打开选字目标。
    if (_pressed != null) {
      _expiry = Timer(kLongPressTimeout, () => _pressed = null);
    }
  }

  void _tap() {
    _expiry?.cancel();
    final link = _pressed;
    _pressed = null;
    final controller = widget.controller;
    if (link != null &&
        controller is LinkTextEditingController &&
        controller.text == _pressedText) {
      controller.onLinkTap?.call(link);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _pointerDown,
    onPointerMove: (event) {
      if (_downPosition != null &&
          (event.position - _downPosition!).distance > kTouchSlop) {
        _pressed = null;
      }
    },
    onPointerUp: (event) => _pointers.remove(event.pointer),
    onPointerCancel: (event) {
      _pointers.remove(event.pointer);
      _pressed = null;
    },
    child: widget.builder(_tap),
  );

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}
