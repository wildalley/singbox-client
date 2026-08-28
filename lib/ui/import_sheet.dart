/// Import sheet: subscription URL, share links, JSON config, or a file path.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showImportSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ImportSheet(state: state),
  );
}

/// Labels come from [L10n] at build time, so the enum carries only the icon.
enum _ImportKind {
  paste(Icons.content_paste_outlined),
  file(Icons.folder_open_outlined);

  const _ImportKind(this.icon);

  final IconData icon;
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.state});

  final AppState state;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _contentController = TextEditingController();
  final _nameController = TextEditingController();
  var _kind = _ImportKind.paste;
  var _submitting = false;

  @override
  void dispose() {
    _contentController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _submitting = true);
    final name = _nameController.text.trim();
    if (_kind == _ImportKind.file) {
      await widget.state.importFromFile(content, name: name.isEmpty ? null : name);
    } else {
      await widget.state.importFromText(content, name: name.isEmpty ? null : name);
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.of(context).pop();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _contentController.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, Gap.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: Gap.xl),
                decoration: BoxDecoration(
                  color: palette.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.importTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.importHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Gap.xl),
            SegmentedChoice<_ImportKind>(
              values: _ImportKind.values,
              selected: _kind,
              labelOf: (value) => switch (value) {
                _ImportKind.paste => l10n.importPaste,
                _ImportKind.file => l10n.importFile,
              },
              onChanged: (value) => setState(() => _kind = value),
            ),
            const SizedBox(height: Gap.lg),
            TextField(
              controller: _contentController,
              maxLines: _kind == _ImportKind.file ? 1 : 6,
              minLines: 1,
              autocorrect: false,
              enableSuggestions: false,
              style: monoStyle(size: 12, color: palette.text),
              decoration: InputDecoration(
                // Example URLs and paths, not prose: left untranslated.
                hintText: switch (_kind) {
                  _ImportKind.paste => 'https://example.com/sub\nor vless://…',
                  _ImportKind.file => '/sdcard/Download/config.json',
                },
                suffixIcon: _kind == _ImportKind.paste
                    ? IconButton(
                        onPressed: _pasteFromClipboard,
                        tooltip: l10n.importPasteFromClipboard,
                        icon: const Icon(Icons.content_paste, size: 18),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: Gap.md),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(hintText: l10n.importNameOptional),
            ),
            const SizedBox(height: Gap.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: Text(
                  _submitting ? l10n.importInProgress : l10n.actionImport,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
