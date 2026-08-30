/// How the nodes page orders rows within a source.
library;

import 'node.dart';

enum NodeSort {
  /// The order the source handed over.
  ///
  /// The default, because a subscription's own order often carries meaning the
  /// names do not — tiers, regions, numbering — and reordering it throws that
  /// away for a figure that changes on every probe.
  source('source'),

  /// Fastest measured first, with the nodes that have no figure at the bottom.
  latency('latency');

  const NodeSort(this.key);

  /// Persisted form. A name rather than [index], which would shift under any
  /// later reordering of this enum and silently change what was stored.
  final String key;

  static NodeSort fromKey(String? value) => values.firstWhere(
        (mode) => mode.key == value,
        orElse: () => NodeSort.source,
      );
}

/// [nodes] in [sort] order. Returns a new list; the argument is left alone.
///
/// Ties keep the order the source gave, so two nodes measured at the same
/// millisecond do not swap places between builds — `List.sort` is not stable on
/// its own, hence the index tiebreak.
List<ProxyNode> sortNodes(List<ProxyNode> nodes, NodeSort sort) {
  if (sort == NodeSort.source) return nodes;
  final ranked = nodes.indexed.toList()
    ..sort((a, b) {
      final byLatency = _rank(a.$2).compareTo(_rank(b.$2));
      return byLatency != 0 ? byLatency : a.$1.compareTo(b.$1);
    });
  return [for (final entry in ranked) entry.$2];
}

/// Sort key: the measured figure, or past every real one for the two states that
/// have none.
///
/// Untested sorts behind every measured node but ahead of unreachable: no probe
/// yet is an open question, a failed probe is an answer. Neither belongs at the
/// top of a list the user asked to be ordered by speed.
int _rank(ProxyNode node) => switch (node.latencyMs) {
      null => 1 << 40,
      < 0 => 1 << 41,
      final value => value,
    };
