part of 'home_page.dart';

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
