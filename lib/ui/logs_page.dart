/// Runtime log viewer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.state});

  final AppState state;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _scrollController = ScrollController();
  var _follow = true;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!_follow || !_scrollController.hasClients) return;
    // Jump after the frame that renders the new entry, or the extent is stale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_follow || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final logs = widget.state.logs;

    return PageFrame(
      title: l10n.logsTitle,
      subtitle: logs.isEmpty
          ? l10n.logsNothingLogged
          : l10n.logsEntryCount(logs.length),
      trailing: Row(
        children: [
          IconButton(
            tooltip: _follow ? l10n.logsFollowing : l10n.logsPaused,
            onPressed: () => setState(() => _follow = !_follow),
            icon: Icon(
              _follow ? Icons.vertical_align_bottom : Icons.pause,
              size: 20,
              color: _follow ? palette.violetSoft : palette.muted,
            ),
          ),
          IconButton(
            tooltip: l10n.logsCopyAll,
            onPressed: logs.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: logs.map((entry) => entry.message).join('\n'),
                      ),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.logsCopied)),
                    );
                  },
            icon: const Icon(Icons.copy_all_outlined, size: 20),
          ),
        ],
      ),
      children: [
        if (logs.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: l10n.logsNoneYet,
            message: l10n.logsConnectToSee,
          )
        else
          Panel(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.md,
            ),
            child: SizedBox(
              height: 460,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final entry = logs[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _clock(entry.at),
                          style: monoStyle(size: 10, color: palette.faint),
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: SelectableText(
                            entry.message,
                            style: monoStyle(
                              size: 11,
                              color: _colorFor(palette, entry.message),
                              weight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';

  /// sing-box prefixes its lines with a level; tint the ones that matter.
  ///
  /// Matching is on the engine's own English level words, which are not
  /// localized, so this stays independent of the UI language.
  static Color _colorFor(AppPalette palette, String message) {
    final lower = message.toLowerCase();
    if (lower.contains('error') || lower.contains('fatal')) {
      return palette.danger;
    }
    if (lower.contains('warn')) return palette.amber;
    return palette.muted;
  }
}
