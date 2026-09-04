part of 'home_page.dart';

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
