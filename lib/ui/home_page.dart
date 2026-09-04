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

part 'home_active_node.dart';
part 'home_connection.dart';
part 'home_dashboard.dart';
part 'home_traffic.dart';

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

String? _coverageLabel(L10n l10n, ProxyCoverage? coverage) =>
    switch (coverage) {
      null => null,
      ProxyCoverage.tun => l10n.homeCoverageTun,
      ProxyCoverage.systemProxy => l10n.homeCoverageSystemProxy,
      ProxyCoverage.systemProxyUnavailable =>
        l10n.homeCoverageSystemProxyUnavailable,
      ProxyCoverage.localProxy => l10n.homeCoverageLocalProxy,
    };

String _stageDetail(L10n l10n, AppState state) {
  final proxy = state.proxyState;
  return switch (proxy.stage) {
    ProxyStage.connected => _connectedDetail(l10n, proxy),
    // Engine messages are not translatable and arrive already redacted, but the
    // failures the app detected itself travel as a marker — so both go through
    // the notice mapping rather than being printed raw.
    ProxyStage.error => proxy.message == null
        ? l10n.homeCheckTheLogs
        : noticeText(l10n, AppState.noticeFor(proxy.message!)),
    _ => state.nodes.isEmpty ? l10n.homeNoNodesYet : l10n.homeReadyToConnect,
  };
}

String _connectedDetail(L10n l10n, ProxyState proxy) {
  final coverage = _coverageLabel(l10n, proxy.coverage);
  if (coverage == null) {
    return proxy.since == null
        ? l10n.homeProtected
        : l10n.homeProtectedFor(
            formatUptime(clockNow().difference(proxy.since!)));
  }
  final uptime = proxy.since == null
      ? null
      : formatUptime(clockNow().difference(proxy.since!));
  return [coverage, if (uptime != null) uptime].join(' · ');
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
