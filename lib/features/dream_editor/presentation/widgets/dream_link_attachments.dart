import 'package:flutter/material.dart';
import 'package:morpheus/features/dream_editor/application/dream_editor_controller.dart';
import 'package:morpheus/features/dream_editor/domain/dream_link.dart';
import 'package:morpheus/l10n/app_text.dart';

enum _LinkAction { open, edit, delete }

/// 链接卡片只展示用户保存的信息，不自动联网抓标题、封面或网页预览。
class DreamLinkAttachments extends StatelessWidget {
  const DreamLinkAttachments({
    super.key,
    required this.links,
    required this.date,
    required this.controller,
    required this.enabled,
  });
  final List<DreamLink> links;
  final DateTime date;
  final DreamEditorController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final revision = controller.dateRevision;
    return Column(
      children: [
        for (final link in links)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey('dream-link-${link.id}'),
                leading: Icon(
                  link.kind == DreamLinkKind.music
                      ? Icons.music_note_outlined
                      : Icons.link,
                ),
                title: Text(
                  link.title ?? link.url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: link.title == null
                    ? null
                    : Text(
                        link.url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: enabled
                    ? () => controller.openLink(
                        date: date,
                        loadRevision: revision,
                        link: link,
                      )
                    : null,
                trailing: PopupMenuButton<_LinkAction>(
                  key: ValueKey('link-options-${link.id}'),
                  tooltip: context.l10n.linkOptions,
                  enabled: enabled,
                  onSelected: (action) {
                    switch (action) {
                      case _LinkAction.open:
                        controller.openLink(
                          date: date,
                          loadRevision: revision,
                          link: link,
                        );
                      case _LinkAction.edit:
                        showDreamLinkEditor(
                          context: context,
                          controller: controller,
                          date: date,
                          kind: link.kind,
                          existing: link,
                          loadRevision: revision,
                        );
                      case _LinkAction.delete:
                        controller.removeLink(
                          date: date,
                          loadRevision: revision,
                          id: link.id,
                        );
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _LinkAction.open,
                      child: Text(context.l10n.openLink),
                    ),
                    PopupMenuItem(
                      value: _LinkAction.edit,
                      child: Text(context.l10n.editLink),
                    ),
                    PopupMenuItem(
                      value: _LinkAction.delete,
                      child: Text(context.l10n.deleteLink),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LinkDraft {
  const _LinkDraft(this.url, this.title);
  final String url;
  final String title;
}

/// 对话框只收集并验证输入，提交后仍由Controller修改同一份草稿。
/// 捕获日期与加载版本，避免通知切日、再切回来时旧对话框重新写入旧表单。
Future<void> showDreamLinkEditor({
  required BuildContext context,
  required DreamEditorController controller,
  required DateTime date,
  required DreamLinkKind kind,
  DreamLink? existing,
  int? loadRevision,
}) async {
  final revision = loadRevision ?? controller.dateRevision;
  final draft = await showDialog<_LinkDraft>(
    context: context,
    builder: (context) => _DreamLinkEditor(kind: kind, existing: existing),
  );
  if (!context.mounted || draft == null) return;
  controller.putLink(
    date: date,
    loadRevision: revision,
    id: existing?.id,
    url: draft.url,
    title: draft.title,
    kind: kind,
  );
}

class _DreamLinkEditor extends StatefulWidget {
  const _DreamLinkEditor({required this.kind, this.existing});
  final DreamLinkKind kind;
  final DreamLink? existing;
  @override
  State<_DreamLinkEditor> createState() => _DreamLinkEditorState();
}

class _DreamLinkEditorState extends State<_DreamLinkEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url = TextEditingController(
    text: widget.existing?.url ?? '',
  );
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _LinkDraft(_url.text, _title.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.existing != null
          ? context.l10n.editLink
          : widget.kind == DreamLinkKind.music
          ? context.l10n.addMusicLink
          : context.l10n.addWebLink,
    ),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const Key('link-url-field'),
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: context.l10n.linkUrlLabel,
              hintText: context.l10n.linkUrlHint,
            ),
            validator: (value) => DreamLink.parseUrl(value ?? '') == null
                ? context.l10n.linkInvalidUrl
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('link-title-field'),
            controller: _title,
            decoration: InputDecoration(labelText: context.l10n.linkTitleLabel),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        key: const Key('save-link-button'),
        onPressed: _submit,
        child: Text(context.l10n.saveLink),
      ),
    ],
  );
}
