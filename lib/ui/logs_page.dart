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
    if (!_follow) return;
    // `hasClients` is deliberately not checked here, only inside the callback.
    //
    // The first batch of lines arrives while the page is still showing its empty
    // state, so there is no ListView and no attached controller *yet* — but there
    // will be one by the end of the frame those lines render in. Checking early
    // returned before scheduling anything, and the log opened scrolled to the top
    // and stayed there. It used to hide behind the old per-line notifications:
    // line two found a controller even though line one did not.
    //
    // After the frame either way, or the extent is stale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_follow || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      final gap = target - position.pixels;

      // A jump, not an animation, and on purpose.
      //
      // Following a live log means arriving at the bottom before the next line
      // does. An animation started per line would still be running when the next
      // one lands, so each would retarget the last and the view would drift
      // behind the engine — smooth, and showing the wrong lines. The reason it
      // reads as calm rather than jarring is that the step is one row: at that
      // distance there is nothing to ease.
      //
      // The exception is a big gap, which is not the follow case at all — it is
      // the user turning follow back on after scrolling up. That one is a
      // deliberate move to a different part of the log, so it gets eased.
      if (gap > _easeFollowFrom) {
        _scrollController.animateTo(
          target,
          duration: Motion.normal,
          curve: Motion.curve,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  /// Flips follow, and eases to the bottom when turning it back on.
  ///
  /// Turning it on is a request to go where the log is, which may be a long way
  /// from where the user was reading — so it is animated, unlike the per-line
  /// step. Turning it off just stops.
  void _toggleFollow() {
    setState(() => _follow = !_follow);
    if (!_follow || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: Motion.normal,
      curve: Motion.curve,
    );
  }

  /// Distance past which catching up is animated rather than jumped, in pixels.
  ///
  /// About four rows. Below that it is a live log advancing and an animation
  /// would fight the next line; above it, the user is somewhere else in the log
  /// and deserves to see where they are being taken.
  static const _easeFollowFrom = 80.0;

  @override
  Widget build(BuildContext context) =>
      PageBody(state: widget.state, builder: _build);

  Widget _build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final logs = widget.state.logs;

    return PageFrame(
      // Fill only when there is a pane to fill. The empty state is a short card
      // and stretching it to the viewport would look broken.
      fill: logs.isNotEmpty,
      title: l10n.logsTitle,
      subtitle: logs.isEmpty
          ? l10n.logsNothingLogged
          : l10n.logsEntryCount(logs.length),
      trailing: Row(
        children: [
          IconButton(
            tooltip: _follow ? l10n.logsFollowing : l10n.logsPaused,
            onPressed: _toggleFollow,
            // Cross-faded and turned rather than swapped: the two icons mean the
            // same control in two states, and a hard cut reads as a different
            // button appearing.
            icon: AnimatedSwitcher(
              duration: motionOf(context, Motion.fast),
              switchInCurve: Motion.curve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                _follow ? Icons.vertical_align_bottom : Icons.pause,
                // Keyed, or AnimatedSwitcher sees one Icon widget of the same
                // type and cross-fades nothing.
                key: ValueKey(_follow),
                size: 20,
                color: _follow ? palette.violetSoft : palette.muted,
              ),
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
            // One selection region for the whole log, rather than a selectable
            // widget per line. Two reasons, and the second is the one a user
            // notices: a SelectableText each brings its own registrar and gesture
            // recognisers, and all of them are rebuilt whenever a line arrives —
            // measured at roughly four times the cost of any other page. And a
            // per-line widget can only select one line, so a stack trace could
            // not be dragged over. This way selection crosses lines.
            child: SelectionArea(
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
                          child: Text(
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

  static String _clock(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:'
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
