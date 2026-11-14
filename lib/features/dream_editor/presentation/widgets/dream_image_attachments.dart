import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/data/image_attachment_service.dart';
import 'package:morpheus/features/dream_editor/domain/dream_image.dart';
import 'package:morpheus/l10n/app_text.dart';

/// 图片不裁切：每张占同样的可用宽度，高度由原始像素比例决定。
/// 页面左右各留 8px；缩略图按显示尺寸解码，避免同时解码多张相册原图。
class DreamImageAttachments extends StatelessWidget {
  const DreamImageAttachments({
    super.key,
    required this.images,
    required this.controller,
    required this.enabled,
  });
  final List<DreamImage> images;
  final DreamEditorController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final image in images)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Semantics(
            button: true,
            label: context.l10n.viewImage,
            child: GestureDetector(
              key: ValueKey('dream-image-${image.fileName}'),
              onTap: () => _view(context, image),
              onLongPress: enabled ? () => _removeMenu(context, image) : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: image.aspectRatio,
                  child: _StoredImage(image: image),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Future<void> _removeMenu(BuildContext context, DreamImage image) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(context.l10n.deleteImage),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (remove == true) controller.removeImage(image);
  }

  void _view(BuildContext context, DreamImage image) {
    // 大图用独立模态页，返回只关闭查看器；右下角删除走同一 Controller 草稿队列。
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: _StoredImage(image: image, fullSize: true),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  tooltip: context.l10n.closeImage,
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              if (enabled)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: IconButton(
                    key: const Key('delete-full-image'),
                    tooltip: context.l10n.deleteImage,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      controller.removeImage(image);
                      Navigator.pop(context);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoredImage extends ConsumerStatefulWidget {
  const _StoredImage({required this.image, this.fullSize = false});
  final DreamImage image;
  final bool fullSize;
  @override
  ConsumerState<_StoredImage> createState() => _StoredImageState();
}

class _StoredImageState extends ConsumerState<_StoredImage> {
  late Future<File> _file;
  @override
  void initState() {
    super.initState();
    _file = ref.read(imageAttachmentServiceProvider).fileFor(widget.image);
  }

  @override
  void didUpdateWidget(_StoredImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.fileName != widget.image.fileName) {
      _file = ref.read(imageAttachmentServiceProvider).fileFor(widget.image);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        context.l10n.imageUnavailable,
        style: TextStyle(color: widget.fullSize ? Colors.white : null),
      ),
    );
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.hasError) return fallback;
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, constraints) => Image.file(
            snapshot.data!,
            fit: BoxFit.contain,
            cacheWidth: widget.fullSize
                ? null
                : (constraints.maxWidth *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
            errorBuilder: (context, error, stack) => fallback,
          ),
        );
      },
    );
  }
}

/// 三行附件菜单锚点固定在加号上方；菜单总高度随字号变化，避免覆盖加号。
class AddAttachmentButton extends StatelessWidget {
  const AddAttachmentButton({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onAddImage,
    required this.onAddWeb,
    required this.onAddMusic,
  });
  final bool enabled;
  final bool busy;
  final VoidCallback onAddImage;
  final VoidCallback onAddWeb;
  final VoidCallback onAddMusic;
  @override
  Widget build(BuildContext context) {
    final menuHeight = MediaQuery.textScalerOf(context).scale(20) + 28;
    return MenuAnchor(
      alignmentOffset: Offset(0, -menuHeight * 3 - 8),
      style: const MenuStyle(
        alignment: Alignment.topLeft,
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        MenuItemButton(
          key: const Key('add-image-menu-item'),
          style: MenuItemButton.styleFrom(minimumSize: Size(160, menuHeight)),
          onPressed: enabled ? onAddImage : null,
          leadingIcon: const Icon(Icons.image_outlined),
          child: Text(context.l10n.addImage),
        ),
        MenuItemButton(
          key: const Key('add-web-link-menu-item'),
          style: MenuItemButton.styleFrom(minimumSize: Size(160, menuHeight)),
          onPressed: enabled ? onAddWeb : null,
          leadingIcon: const Icon(Icons.link),
          child: Text(context.l10n.addWebLink),
        ),
        MenuItemButton(
          key: const Key('add-music-link-menu-item'),
          style: MenuItemButton.styleFrom(minimumSize: Size(160, menuHeight)),
          onPressed: enabled ? onAddMusic : null,
          leadingIcon: const Icon(Icons.music_note_outlined),
          child: Text(context.l10n.addMusicLink),
        ),
      ],
      builder: (context, menu, child) => IconButton(
        key: const Key('add-attachment-button'),
        tooltip: context.l10n.addAttachment,
        onPressed: enabled
            ? () {
                FocusScope.of(context).unfocus();
                menu.isOpen ? menu.close() : menu.open();
              }
            : null,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
    );
  }
}
