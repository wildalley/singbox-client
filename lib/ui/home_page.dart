/// Home dashboard: connection anchor, live traffic, and the active node.
///
/// The layout forks at [_dashboardWidth]. Narrow screens keep the dial — one
/// large tappable control is the right thing to hand a thumb. Wide screens get
/// a dashboard instead, because the dial scaled up is just a big circle
/// surrounded by empty space.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../models/proxy_state.dart';
import '../state/app_state.dart';
import 'clock.dart';
import 'components.dart';
import 'notice_text.dart';
import 'theme.dart';
import 'widgets.dart';

/// Above this the page switches from dial to dashboard. Set where four metric
/// cards still have room for a mono value each without ellipsing.
const _dashboardWidth = 900.0;

/// Where the traffic card and the node card stop stacking.
const _twoColumnWidth = 640.0;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Drives the uptime label without rebuilding on every traffic event.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.state.isConnected) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final state = widget.state;
    final traffic = state.traffic;
    final connected = state.isConnected;

    return PageFrame(
      title: _greeting(l10n),
      subtitle: l10n.homeSubtitle,
      trailing: IconButton(
        onPressed: state.nodes.isEmpty ? null : state.testLatency,
        tooltip: l10n.actionTestLatency,
        icon: state.isTestingLatency
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.speed_outlined, color: palette.muted),
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > _dashboardWidth) {
              // No session panel here: the metric row above already carries all
              // three of its figures, and repeating them verbatim read as a
              // rendering mistake rather than a summary.
              return _Dashboard(
                state: state,
                onOpenNodes: widget.onOpenNodes,
                downlink: state.downlinkHistory,
                uplink: state.uplinkHistory,
                connections: state.connectionHistory,
                memory: state.memoryHistory,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialLayout(
                  state: state,
                  onOpenNodes: widget.onOpenNodes,
                  downlink: state.downlinkHistory,
                  uplink: state.uplinkHistory,
                ),
                const SizedBox(height: Gap.xxl),
                SectionLabel(connected ? l10n.homeSession : l10n.homeTotals),
                Panel(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stat.count(
                          label: l10n.homeDownloaded,
                          value: traffic.downlinkTotal,
                          format: formatBytes,
                        ),
                      ),
                      Expanded(
                        child: _Stat.count(
                          label: l10n.homeUploaded,
                          value: traffic.uplinkTotal,
                          format: formatBytes,
                        ),
                      ),
                      Expanded(
                        child: _Stat.count(
                          label: l10n.homeConnections,
                          value: traffic.connections,
                          format: (value) => '$value',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _greeting(L10n l10n) {
    final hour = clockNow().hour;
    if (hour < 5) return l10n.greetingNight;
    if (hour < 12) return l10n.greetingMorning;
    if (hour < 18) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
  }
}

// --------------------------------------------------------------- shared bits

/// Accent for the current stage: mint healthy, danger failed, violetSoft
/// otherwise.
///
/// Every caller draws this as a foreground or a decoration — the dial's icon and
/// label, the hero icon, the [StatusPill] dot and text — so the idle stage takes
/// `violetSoft`, not `violet`. `violet` is a fill: it sits at ~2.4:1 on surface,
/// which left "Disconnected" reading as violet on violet. The one real violet
/// fill, the connect button, sets its own colour and does not come through here.
Color _stageAccent(AppPalette palette, ProxyStage stage) => switch (stage) {
      ProxyStage.connected => palette.mint,
      ProxyStage.error => palette.danger,
      _ => palette.violetSoft,
    };

String _stageLabel(L10n l10n, ProxyStage stage) => switch (stage) {
      ProxyStage.connected => l10n.stageConnected,
      ProxyStage.starting => l10n.stageConnecting,
      ProxyStage.stopping => l10n.stageDisconnecting,
      ProxyStage.requestingPermission => l10n.stageAwaitingPermission,
      ProxyStage.error => l10n.stageFailed,
      ProxyStage.disconnected => l10n.stageDisconnected,
    };

String _stageDetail(L10n l10n, AppState state) {
  final proxy = state.proxyState;
  return switch (proxy.stage) {
    ProxyStage.connected => proxy.since == null
        ? l10n.homeProtected
        : l10n.homeProtectedFor(
            formatUptime(clockNow().difference(proxy.since!))),
    // Engine messages are not translatable and arrive already redacted, but the
    // failures the app detected itself travel as a marker — so both go through
    // the notice mapping rather than being printed raw.
    ProxyStage.error => proxy.message == null
        ? l10n.homeCheckTheLogs
        : noticeText(l10n, AppState.noticeFor(proxy.message!)),
    _ => state.nodes.isEmpty ? l10n.homeNoNodesYet : l10n.homeReadyToConnect,
  };
}

String _latencyText(L10n l10n, int? latency) => switch (latency) {
      null => l10n.nodesUntested,
      < 0 => l10n.nodesUnreachable,
      final value => '$value ms',
    };

/// What the active exit is called.
///
/// Auto names no node, so [AppState.selectedNode] is null under it — but it is a
/// selection the user made, and reading it as "no node selected" would say the
/// opposite. Every card that names the exit goes through here.
String _exitName(L10n l10n, AppState state) => state.isAutoSelected
    ? l10n.nodesAuto
    : state.selectedNode?.name ?? l10n.homeNoNodeSelected;

/// Nodes that answered a probe. A negative latency is a recorded failure, so it
/// counts as tested but not as available.
int _availableNodes(List<ProxyNode> nodes) =>
    nodes.where((node) => (node.latencyMs ?? -1) >= 0).length;

/// The primary action, shared by both layouts so the label and disabled rules
/// can only be defined once.
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final connected = state.isConnected;
    final empty = state.nodes.isEmpty;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: state.isBusy
            ? null
            : (empty ? onOpenNodes : state.toggleConnection),
        icon: Icon(
          switch (true) {
            _ when empty => Icons.add_rounded,
            _ when connected => Icons.stop_rounded,
            _ => Icons.power_settings_new_rounded,
          },
          size: 18,
        ),
        label: Text(
          switch (true) {
            _ when empty => l10n.homeAddNodes,
            _ when connected => l10n.actionDisconnect,
            _ => l10n.actionConnect,
          },
        ),
        style: FilledButton.styleFrom(
          // Disconnect is the quieter action, so it drops the brand fill — but
          // it keeps a tinted face and a matching border. A bare surface3 bar
          // read as a disabled control rather than the way out of the tunnel.
          backgroundColor:
              connected ? tintFill(palette.danger) : palette.violet,
          foregroundColor: connected ? palette.danger : Colors.white,
          side: connected
              ? BorderSide(color: palette.danger.withValues(alpha: .38))
              : null,
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ wide dashboard

/// Wide-screen layout: a lit hero beside the latency ring, then a metric row.
class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.state,
    required this.onOpenNodes,
    required this.downlink,
    required this.uplink,
    required this.connections,
    required this.memory,
  });

  final AppState state;
  final VoidCallback onOpenNodes;
  final List<int> downlink;
  final List<int> uplink;
  final List<int> connections;
  final List<int> memory;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final traffic = state.traffic;
    final connected = state.isConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // IntrinsicHeight, not CrossAxisAlignment.stretch: the page scrolls, so
        // the Row's own height is unbounded and stretch would ask the cards to
        // be infinitely tall. This measures the taller card and matches it.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _HeroCard(state: state, onOpenNodes: onOpenNodes),
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                flex: 2,
                child: _RingCard(state: state, onOpenNodes: onOpenNodes),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xxl),
        SectionLabel(l10n.homeOverview),
        // Same reason as the hero row: equal-height cards without asking for
        // infinite height inside the scroll view.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MetricCard(
                  label: l10n.homeDownload,
                  value: traffic.downlinkTotal,
                  format: formatBytes,
                  caption: connected ? formatRate(traffic.downlink) : '—',
                  icon: Icons.arrow_downward_rounded,
                  accent: palette.sky,
                  chart: Sparkline(
                    values: downlink,
                    color: connected ? palette.sky : palette.faint,
                    secondColor: connected ? palette.violetSoft : null,
                    height: 30,
                  ),
                ),
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: MetricCard(
                  label: l10n.homeUpload,
                  value: traffic.uplinkTotal,
                  format: formatBytes,
                  caption: connected ? formatRate(traffic.uplink) : '—',
                  icon: Icons.arrow_upward_rounded,
                  accent: palette.mint,
                  chart: Sparkline(
                    values: uplink,
                    color: connected ? palette.mint : palette.faint,
                    secondColor: connected ? palette.sky : null,
                    height: 30,
                  ),
                ),
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: MetricCard(
                  label: l10n.homeConnections,
                  value: traffic.connections,
                  format: (value) => '$value',
                  icon: Icons.hub_outlined,
                  accent: palette.violetSoft,
                  chart: MiniBars(
                    values: connections,
                    color: connected ? palette.violetSoft : palette.faint,
                    height: 30,
                  ),
                ),
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: MetricCard(
                  label: l10n.homeMemory,
                  // The runtime only reports memory while it is running; zero
                  // would read as a measurement, so idle shows a dash.
                  value: traffic.memory,
                  format: (value) => connected ? formatBytes(value) : '—',
                  // No caption: the transfer cards put a rate here, and memory
                  // has no second figure of its own. It carried the node's
                  // protocol and latency, which belongs to the node panel and
                  // read here as if it described the memory reading.
                  icon: Icons.memory_outlined,
                  accent: palette.amber,
                  // A level rather than a rate, so it gets a line like the
                  // transfer cards rather than the connection count's bars.
                  chart: Sparkline(
                    values: memory,
                    color: connected ? palette.amber : palette.faint,
                    height: 30,
                    level: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xxl),
        SectionLabel(l10n.homeTrafficFlow),
        Panel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PanelTitle(
                      title: l10n.homeLiveTraffic,
                      icon: Icons.show_chart_rounded,
                    ),
                  ),
                  _FlowLegend(
                    label: l10n.homeDownload,
                    color: connected ? palette.sky : palette.faint,
                  ),
                  const SizedBox(width: Gap.md),
                  _FlowLegend(
                    label: l10n.homeUpload,
                    color: connected ? palette.mint : palette.faint,
                  ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              TrafficFlowChart(
                downlink: downlink,
                uplink: uplink,
                downColor: connected ? palette.sky : palette.faint,
                upColor: connected ? palette.mint : palette.faint,
              ),
              const SizedBox(height: Gap.md),
              // The window is fixed, so the axis can be stated rather than
              // drawn with tick labels the samples don't carry timestamps for.
              Text(
                l10n.homeLastMinute,
                style: monoStyle(color: palette.faint, size: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dot-and-label key for one series on the traffic flow chart. Two lines share
/// one scale there, so which is which has to be stated rather than guessed.
class _FlowLegend extends StatelessWidget {
  const _FlowLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// The dashboard's anchor: stage, node, session facts, and the primary action.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final proxy = state.proxyState;
    final accent = _stageAccent(palette, proxy.stage);
    final connected = proxy.isConnected;
    final nodes = state.nodes;

    return GlowCard(
      accent: accent,
      lit: connected || proxy.stage == ProxyStage.error,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: ConsoleBackground(
          accent: accent,
          // The field wakes up only when there is a tunnel to describe (or one
          // is actively being established). The disconnected dashboard keeps
          // the same grid and vignette, but stays deliberately still.
          showSignals: connected || state.isBusy,
          animate: connected || state.isBusy,
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      connected ? Icons.shield_rounded : Icons.bolt_rounded,
                      color: accent,
                      size: 20,
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        _exitName(l10n, state),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    StatusPill(
                      label: _stageLabel(l10n, proxy.stage),
                      color: accent,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  _stageDetail(l10n, state),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: Gap.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Stat.text(
                        label: l10n.homeUptime,
                        value: connected && proxy.since != null
                            ? formatUptime(clockNow().difference(proxy.since!))
                            : '—',
                      ),
                    ),
                    Expanded(
                      child: _Stat.text(
                        label: l10n.homeAvailableNodes,
                        value: l10n.homeAvailableOf(
                          _availableNodes(nodes),
                          nodes.length,
                        ),
                      ),
                    ),
                  ],
                ),
                // Takes up whatever height the taller neighbouring card forces on
                // this one. Without it the surplus fell below the button as a
                // band of bare backdrop.
                const Spacer(),
                const SizedBox(height: Gap.xl),
                _ConnectButton(state: state, onOpenNodes: onOpenNodes),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The latency ring plus the shortcut into the node list.
class _RingCard extends StatelessWidget {
  const _RingCard({required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final node = state.selectedNode;
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(title: l10n.homeActiveNode, icon: Icons.public),
          const SizedBox(height: Gap.lg),
          Center(
            child: RingGauge(
              latencyMs: node?.latencyMs,
              label: node?.latencyMs == null
                  ? l10n.homeUntestedNodes
                  : l10n.homeLatency,
            ),
          ),
          const SizedBox(height: Gap.lg),
          Center(
            child: Text(
              state.isAutoSelected
                  ? l10n.nodesAutoBody
                  : node?.regionHint ?? l10n.homeImportPrompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: Gap.lg),
          _ExitAddressRow(state: state),
          const SizedBox(height: Gap.md),
          OutlinedButton(
            onPressed: onOpenNodes,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 42),
            ),
            // On the node list rather than on the selection: under Auto there is
            // no node to name, and offering to add one would be wrong with a
            // subscription already imported.
            child: Text(
                state.nodes.isEmpty ? l10n.homeAddNodes : l10n.homeChangeNode),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- dial layout

/// Narrow-screen layout: the dial, then traffic and node cards.
class _DialLayout extends StatelessWidget {
  const _DialLayout({
    required this.state,
    required this.onOpenNodes,
    required this.downlink,
    required this.uplink,
  });

  final AppState state;
  final VoidCallback onOpenNodes;
  final List<int> downlink;
  final List<int> uplink;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ConnectionCard(state: state, onOpenNodes: onOpenNodes),
        const SizedBox(height: Gap.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final trafficCard = _TrafficCard(
              connected: state.isConnected,
              downlink: downlink,
              uplink: uplink,
              state: state,
            );
            final node =
                _ActiveNodeCard(state: state, onOpenNodes: onOpenNodes);
            if (constraints.maxWidth > _twoColumnWidth) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: trafficCard),
                  const SizedBox(width: Gap.lg),
                  Expanded(flex: 2, child: node),
                ],
              );
            }
            return Column(
              children: [trafficCard, const SizedBox(height: Gap.lg), node],
            );
          },
        ),
      ],
    );
  }
}

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

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.connected,
    required this.downlink,
    required this.uplink,
    required this.state,
  });

  final bool connected;
  final List<int> downlink;
  final List<int> uplink;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final traffic = state.traffic;
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(
            title: l10n.homeLiveTraffic,
            icon: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: Gap.xl),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: l10n.homeDownload,
                  value: traffic.downlinkTotal,
                  format: formatBytes,
                  rate: connected ? formatRate(traffic.downlink) : '—',
                  icon: Icons.arrow_downward_rounded,
                  // Same pairing as the wide layout's flow panel: sky down,
                  // mint up. These label the chart below, so they have to be
                  // the colours it is actually drawn in.
                  color: connected ? palette.sky : palette.faint,
                ),
              ),
              const SizedBox(width: Gap.xl),
              Expanded(
                child: _Metric(
                  label: l10n.homeUpload,
                  value: traffic.uplinkTotal,
                  format: formatBytes,
                  rate: connected ? formatRate(traffic.uplink) : '—',
                  icon: Icons.arrow_upward_rounded,
                  color: connected ? palette.mint : palette.faint,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xl),
          // Both series, not just downlink. The two figures above name Download
          // and Upload, so a single downlink curve under them was a chart that
          // answered for one of the two things its own legend promised — and its
          // violetSoft-to-sky gradient read as a third colour belonging to
          // neither. Same widget and scale as the wide layout, at the narrow
          // card's height.
          TrafficFlowChart(
            downlink: downlink,
            uplink: uplink,
            downColor: connected ? palette.sky : palette.faint,
            upColor: connected ? palette.mint : palette.faint,
            height: 62,
          ),
          const SizedBox(height: Gap.md),
          // Same axis statement as the wide layout's flow panel: the window is
          // fixed, and without it the strip is a curve over an unnamed span.
          Text(
            l10n.homeLastMinute,
            style: monoStyle(color: palette.faint, size: 11),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.format,
    required this.rate,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final String Function(int value) format;
  final String rate;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: Gap.sm),
        AnimatedCount(
          value: value,
          format: format,
          style: monoStyle(
            size: 19,
            weight: FontWeight.w600,
            color: context.palette.text,
          ),
        ),
        const SizedBox(height: 3),
        Text(rate, style: monoStyle(size: 11, color: color)),
      ],
    );
  }
}

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
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)
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
    final (String text, Color colour) = switch ((connected, checking, address)) {
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
