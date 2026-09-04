part of 'home_page.dart';

class _ActiveNodeCard extends StatelessWidget {
  const _ActiveNodeCard({required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final node = state.selectedNode;
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(title: l10n.homeActiveNode, icon: Icons.public),
          const SizedBox(height: Gap.xl),
          // Auto comes first because it also has no node: it reaches this card as
          // a null selection, but it is one the user made.
          if (state.isAutoSelected)
            _ActiveNodeRow(
              icon: Icons.bolt_rounded,
              title: l10n.nodesAuto,
              // No latency to put on the right: the engine's pick can change
              // between frames, so any figure here would name the wrong node.
              subtitle: l10n.nodesAutoBody,
            )
          else if (node == null)
            Text(
              l10n.homeImportPrompt,
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            _ActiveNodeRow(
              icon: Icons.location_on_outlined,
              title: node.regionHint,
              subtitle: node.protocol.label,
              trailing: Text(
                _latencyText(l10n, node.latencyMs),
                style: monoStyle(color: latencyColor(palette, node.latencyMs)),
              ),
            ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onOpenNodes,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 42),
            ),
            // Keyed to the node list, not the selection: under Auto there is
            // nothing to add, and the choice on offer is still a change.
            child: Text(
              state.nodes.isEmpty ? l10n.homeAddNodes : l10n.homeChangeNode,
            ),
          ),
        ],
      ),
    );
  }
}

/// The named exit inside [_ActiveNodeCard]: tile, two lines, optional figure.
///
/// Extracted because Auto and a node differ only in what fills those slots, and
/// having the layout twice invited them to drift apart.
class _ActiveNodeRow extends StatelessWidget {
  const _ActiveNodeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Right-hand figure, omitted when there is nothing true to put there.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: palette.violet.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: palette.violetSoft, size: 20),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  /// A reading that is already text: an uptime clock, a composed "N of M".
  ///
  /// Deliberately not tweened. The uptime is a clock — interpolating it would
  /// walk through times that never elapsed — and the node count is a localised
  /// sentence, not a number with a unit.
  const _Stat.text({required this.label, required String value})
      : text = value,
        count = null,
        formatter = null;

  /// A number that ticks, so it counts to its new value.
  const _Stat.count({
    required this.label,
    required int value,
    required String Function(int value) format,
  })  : count = value,
        formatter = format,
        text = null;

  final String label;
  final String? text;
  final int? count;

  /// Only set by [_Stat.count], which requires it — so the read in [build] is
  /// guarded by which constructor ran, not by a runtime check.
  final String Function(int value)? formatter;

  @override
  Widget build(BuildContext context) {
    final style = monoStyle(
      size: 15,
      weight: FontWeight.w600,
      color: context.palette.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        if (text case final value?)
          Text(value,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style)
        else
          AnimatedCount(value: count!, format: formatter!, style: style),
      ],
    );
  }
}

/// One line reporting the address the outside world sees.
///
/// The reading every other figure on this screen cannot give. Bytes moving and a
/// node selected look the same whether the traffic leaves through the node or
/// straight out of the user's own line, so this is the only thing on the
/// dashboard that actually answers "is it working". Hence the prominence of a
/// row of its own rather than a line in a settings list.
class _ExitAddressRow extends StatelessWidget {
  const _ExitAddressRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final address = state.exitAddress;
    final checking = state.isCheckingExitAddress;
    final connected = state.isConnected;

    // Four states, and they have to stay distinguishable: a dash means nothing
    // was asked, "checking" means in flight, an address is the answer, and
    // "unknown" means it was asked and nothing came back — which is worth
    // telling apart from the dash, because it can mean a tunnel that carries
    // nothing.
    final (String text, Color colour) =
        switch ((connected, checking, address)) {
      (_, true, _) => (l10n.settingsChecking, palette.faint),
      (_, _, final found?) => (found.ip, palette.text),
      (false, _, _) => (l10n.latencyUnknown, palette.faint),
      _ => (l10n.homeExitUnknown, palette.amber),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.travel_explore_outlined, size: 15, color: palette.faint),
          const SizedBox(width: Gap.sm),
          Text(
            l10n.homeExitIp.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(letterSpacing: 1.1),
          ),
          const Spacer(),
          // The address is data, so it is monospaced like every other reading
          // here; it also stops the row twitching as digits change on a refresh.
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: motionOf(context, Motion.normal),
              curve: Motion.curve,
              style: DefaultTextStyle.of(context)
                  .style
                  .merge(monoStyle(color: colour, weight: FontWeight.w600)),
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (address?.countryCode case final code?) ...[
            const SizedBox(width: Gap.sm),
            // The country is the part a user actually reads: it says whether the
            // exit is where they picked, which a bare address does not.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: tintFill(palette.mint),
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: palette.mint.withValues(alpha: .22)),
              ),
              child: Text(
                code,
                style: monoStyle(
                  size: 10,
                  color: palette.mint,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
          IconButton(
            // Left enabled while disconnected on purpose: that is how a user
            // checks what their own address is, and the request only goes out
            // when they ask for it.
            onPressed: checking ? null : state.refreshExitAddress,
            tooltip: l10n.actionRefresh,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: palette.faint,
            icon: checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
