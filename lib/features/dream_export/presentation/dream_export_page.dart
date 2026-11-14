import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_export/data/dream_export_output.dart';
import 'package:morpheus/features/dream_export/data/dream_export_renderer.dart';
import 'package:morpheus/features/dream_export/domain/dream_export_data.dart';
import 'package:morpheus/l10n/app_text.dart';

class DreamExportPage extends ConsumerStatefulWidget {
  const DreamExportPage({super.key, required this.data});
  final DreamExportData data;
  @override
  ConsumerState<DreamExportPage> createState() => _DreamExportPageState();
}

class _DreamExportPageState extends ConsumerState<DreamExportPage> {
  DreamExportImage? _image;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    // 长图解码后的位图可能达数十MB，离开预览时驱逐对应缓存。原PNG仍由
    // 输出中的Future持有，系统分享文件的生命周期独立于页面。
    if (_image != null) unawaited(MemoryImage(_image!.bytes).evict());
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _error = null;
    });
    try {
      final image = await ref
          .read(dreamExportRendererProvider)
          .render(widget.data, isCancelled: () => !mounted);
      if (mounted) {
        setState(() {
          _image = image;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    }
  }

  Future<void> _output(bool save, BuildContext buttonContext) async {
    if (_busy || _image == null) return;
    // 分享popover在iPad必须有锚点。使用被点击按钮的实际屏幕位置，
    // 不硬编码手机尺寸；await前取出，避免异步后使用失效的context。
    final box = buttonContext.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final output = ref.read(dreamExportOutputProvider);
      if (save) {
        await output.save(_image!, widget.data.date);
      } else {
        await output.share(_image!, widget.data.date, origin);
      }
      if (mounted && save) _showMessage(context.l10n.exportSaved);
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is PlatformException && error.code == 'permissionDenied'
              ? context.l10n.exportPermissionDenied
              : save
              ? context.l10n.exportSaveFailed
              : context.l10n.exportShareFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text(context.l10n.exportPreviewTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _image != null
                  ? LayoutBuilder(
                      builder: (context, constraints) => InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: SingleChildScrollView(
                          child: Image.memory(
                            _image!.bytes,
                            width: constraints.maxWidth,
                            fit: BoxFit.fitWidth,
                            semanticLabel: context.l10n.exportImageLabel,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _error == null
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    Text(context.l10n.exportPreparing),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _error is DreamExportTooLarge
                                          ? context.l10n.exportTooLarge
                                          : context.l10n.exportFailed,
                                    ),
                                    TextButton(
                                      onPressed: _generate,
                                      child: Text(context.l10n.retry),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
            ),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .38,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          context.l10n.exportPrivacyNote,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        // Wrap在窄屏或大字号下自动换行，不把两个操作强塞在固定一行。
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            Builder(
                              builder: (buttonContext) => FilledButton.icon(
                                key: const Key('export-save'),
                                onPressed: _busy || _image == null
                                    ? null
                                    : () => _output(true, buttonContext),
                                icon: const Icon(Icons.save_alt),
                                label: Text(context.l10n.exportSaveAlbum),
                              ),
                            ),
                            Builder(
                              builder: (buttonContext) => OutlinedButton.icon(
                                key: const Key('export-share'),
                                onPressed: _busy || _image == null
                                    ? null
                                    : () => _output(false, buttonContext),
                                icon: const Icon(Icons.ios_share),
                                label: Text(context.l10n.exportSystemShare),
                              ),
                            ),
                          ],
                        ),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
