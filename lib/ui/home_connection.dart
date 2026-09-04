part of 'home_page.dart';

/// The visual anchor: a large tappable connection control.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final proxy = state.proxyState;
    final connected = proxy.isConnected;
    final failed = proxy.stage == ProxyStage.error;
    final accent = _stageAccent(palette, proxy.stage);
    final node = state.selectedNode;

    return Panel(
      accent: connected || failed ? accent : null,
      glowing: connected || failed,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          _ConnectionDial(
            accent: accent,
            connected: connected,
            busy: state.isBusy,
            label: _stageLabel(l10n, proxy.stage),
            detail: _stageDetail(l10n, state),
          ),
          const SizedBox(height: Gap.md),
          if (node != null) ...[
            Text(
              node.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 5),
            Text(
              '${node.protocol.label}  ·  ${_latencyText(l10n, node.latencyMs)}',
              style: monoStyle(color: palette.muted),
            ),
          ] else if (state.isAutoSelected) ...[
            // Same two lines as a node, but the second one cannot be a protocol
            // and a latency: which node is carrying the traffic is the engine's
            // to decide, and it can change under this text at any moment.
            Text(
              l10n.nodesAuto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 5),
            Text(
              l10n.nodesAutoBody,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else
            Text(
              l10n.homeNoNodeSelected,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: Gap.lg),
          _ExitAddressRow(state: state),
          const SizedBox(height: Gap.lg),
          _ConnectButton(state: state, onOpenNodes: onOpenNodes),
        ],
      ),
    );
  }
}

/// Concentric rings that pulse while connecting and settle once connected.
class _ConnectionDial extends StatefulWidget {
  const _ConnectionDial({
    required this.accent,
    required this.connected,
    required this.busy,
    required this.label,
    required this.detail,
  });

  final Color accent;
  final bool connected;
  final bool busy;
  final String label;
  final String detail;

  @override
  State<_ConnectionDial> createState() => _ConnectionDialState();
}

class _ConnectionDialState extends State<_ConnectionDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: Motion.slower,
  );

  // MediaQuery is read here rather than in initState, and this also catches the
  // accessibility setting being changed while the dial is on screen.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_ConnectionDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    // An indefinite pulse cannot be expressed as a shorter duration, so reduced
    // motion parks it rather than speeding it up. Ring and glow stay, they just
    // hold still. TickerMode is what stops it ticking on an inactive tab.
    final canAnimate = widget.busy &&
        !MediaQuery.of(context).disableAnimations &&
        TickerMode.valuesOf(context).enabled;
    if (canAnimate) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final intensity = glowIntensity(Theme.of(context).brightness);
    return SizedBox(
      height: 164,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              // While busy the outer ring breathes; otherwise it sits still.
              final expand = widget.busy ? _pulse.value : 0.0;
              return Container(
                width: 150 + expand * 12,
                height: 150 + expand * 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.accent
                        .withValues(alpha: .16 * (1 - expand) + .04),
                  ),
                ),
              );
            },
          ),
          AnimatedContainer(
            duration: Motion.normal,
            curve: Motion.curve,
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Pre-composited against the card rather than left translucent.
              // A BoxShadow paints *behind* its own fill, so a 9%-alpha disc
              // let both glow layers through: the disc rendered as its accent
              // at ~46%, and "Protected · 4h 12m" landed on it at 1.97:1.
              // Opaque keeps the halo outside the circle, where a glow belongs.
              color: Color.alphaBlend(
                widget.accent.withValues(alpha: .09),
                palette.surface,
              ),
              border: Border.all(
                color: widget.accent.withValues(alpha: .38),
                width: 1.5,
              ),
              // The dial is the one element on the narrow layout that carries
              // live state, so it gets the full two-layer glow.
              boxShadow: glow(widget.accent, intensity: intensity),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.connected ? Icons.shield_rounded : Icons.bolt_rounded,
                color: widget.accent,
                size: 26,
              ),
              const SizedBox(height: Gap.sm),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: Text(
                  widget.detail,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
