/// Home dashboard: connection anchor, live traffic, and the active node.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/proxy_state.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Rolling download-rate history for the sparkline.
  final _history = <int>[];

  /// Drives the uptime label without rebuilding on every traffic event.
  Timer? _ticker;

  static const _historyLength = 40;

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
    if (!mounted) return;
    setState(() {
      _history.add(widget.state.isConnected ? widget.state.traffic.downlink : 0);
      if (_history.length > _historyLength) {
        _history.removeRange(0, _history.length - _historyLength);
      }
    });
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
        _ConnectionCard(state: state, onOpenNodes: widget.onOpenNodes),
        const SizedBox(height: Gap.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final trafficCard = _TrafficCard(
              connected: connected,
              // A copy: the painter compares old and new lists, and the same
              // instance would always look unchanged.
              history: List.of(_history),
              state: state,
            );
            final node = _ActiveNodeCard(
              state: state,
              onOpenNodes: widget.onOpenNodes,
            );
            if (constraints.maxWidth > 640) {
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
        const SizedBox(height: Gap.xxl),
        SectionLabel(connected ? l10n.homeSession : l10n.homeTotals),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: _Stat(
                  label: l10n.homeDownloaded,
                  value: formatBytes(traffic.downlinkTotal),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: l10n.homeUploaded,
                  value: formatBytes(traffic.uplinkTotal),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: l10n.homeConnections,
                  value: '${traffic.connectionsOut}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _greeting(L10n l10n) {
    final hour = DateTime.now().hour;
    if (hour < 5) return l10n.greetingNight;
    if (hour < 12) return l10n.greetingMorning;
    if (hour < 18) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
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
    final busy = state.isBusy;
    final failed = proxy.stage == ProxyStage.error;

    final accent = switch (proxy.stage) {
      ProxyStage.connected => palette.mint,
      ProxyStage.error => palette.danger,
      _ => palette.violet,
    };

    final label = switch (proxy.stage) {
      ProxyStage.connected => l10n.stageConnected,
      ProxyStage.starting => l10n.stageConnecting,
      ProxyStage.stopping => l10n.stageDisconnecting,
      ProxyStage.requestingPermission => l10n.stageAwaitingPermission,
      ProxyStage.error => l10n.stageFailed,
      ProxyStage.disconnected => l10n.stageDisconnected,
    };

    final detail = switch (proxy.stage) {
      ProxyStage.connected => proxy.since == null
          ? l10n.homeProtected
          : l10n.homeProtectedFor(
              formatUptime(DateTime.now().difference(proxy.since!))),
      // Engine messages are not translatable; they arrive already redacted.
      ProxyStage.error => proxy.message ?? l10n.homeCheckTheLogs,
      _ => state.nodes.isEmpty ? l10n.homeNoNodesYet : l10n.homeReadyToConnect,
    };

    final node = state.selectedNode;

    return Panel(
      accent: connected || failed ? accent : null,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          _ConnectionDial(
            accent: accent,
            connected: connected,
            busy: busy,
            label: label,
            detail: detail,
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
          ] else
            Text(
              l10n.homeNoNodeSelected,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: Gap.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : (state.nodes.isEmpty ? onOpenNodes : state.toggleConnection),
              icon: Icon(
                switch (true) {
                  _ when state.nodes.isEmpty => Icons.add_rounded,
                  _ when connected => Icons.stop_rounded,
                  _ => Icons.power_settings_new_rounded,
                },
                size: 18,
              ),
              label: Text(
                switch (true) {
                  _ when state.nodes.isEmpty => l10n.homeAddNodes,
                  _ when connected => l10n.actionDisconnect,
                  _ => l10n.actionConnect,
                },
              ),
              style: FilledButton.styleFrom(
                // Disconnect is the quieter action, so it drops the brand fill.
                backgroundColor: connected ? palette.surface3 : palette.violet,
                foregroundColor: connected ? palette.text : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _latencyText(L10n l10n, int? latency) => switch (latency) {
        null => l10n.nodesUntested,
        < 0 => l10n.nodesUnreachable,
        final value => '$value ms',
      };
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
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_ConnectionDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.busy) {
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
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.accent.withValues(alpha: .09),
              border: Border.all(
                color: widget.accent.withValues(alpha: .38),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: .12),
                  blurRadius: 32,
                ),
              ],
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
    required this.history,
    required this.state,
  });

  final bool connected;
  final List<int> history;
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
                  value: formatBytes(traffic.downlinkTotal),
                  rate: connected ? formatRate(traffic.downlink) : '—',
                  icon: Icons.arrow_downward_rounded,
                  color: palette.violetSoft,
                ),
              ),
              const SizedBox(width: Gap.xl),
              Expanded(
                child: _Metric(
                  label: l10n.homeUpload,
                  value: formatBytes(traffic.uplinkTotal),
                  rate: connected ? formatRate(traffic.uplink) : '—',
                  icon: Icons.arrow_upward_rounded,
                  color: palette.mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xl),
          Sparkline(
            values: history,
            color: connected ? palette.violet : palette.faint,
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
    required this.rate,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
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
        Text(
          value,
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
          if (node == null)
            Text(
              l10n.homeImportPrompt,
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.violet.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.location_on_outlined,
                    color: palette.violetSoft,
                    size: 20,
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.regionHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        node.protocol.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  switch (node.latencyMs) {
                    null => l10n.latencyUnknown,
                    < 0 => l10n.latencyFail,
                    final value => '$value ms',
                  },
                  style: monoStyle(color: latencyColor(palette, node.latencyMs)),
                ),
              ],
            ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onOpenNodes,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 42),
            ),
            child: Text(node == null ? l10n.homeAddNodes : l10n.homeChangeNode),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          value,
          style: monoStyle(
            size: 15,
            weight: FontWeight.w600,
            color: context.palette.text,
          ),
        ),
      ],
    );
  }
}
