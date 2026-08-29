/// Node list: search, filter, per-subscription grouping, and selection.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../models/subscription.dart';
import '../state/app_state.dart';
import 'import_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

enum _NodeFilter { all, fast, favorites }

String _filterLabel(L10n l10n, _NodeFilter filter) => switch (filter) {
      _NodeFilter.all => l10n.nodesFilterAll,
      _NodeFilter.fast => l10n.nodesFilterFast,
      _NodeFilter.favorites => l10n.nodesFilterFavorites,
    };

class NodesPage extends StatefulWidget {
  const NodesPage({super.key, required this.state});

  final AppState state;

  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage> {
  final _searchController = TextEditingController();
  var _query = '';
  var _filter = _NodeFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProxyNode> get _visible {
    final query = _query.trim().toLowerCase();
    return widget.state.nodes.where((node) {
      if (query.isNotEmpty && !node.name.toLowerCase().contains(query)) {
        return false;
      }
      return switch (_filter) {
        _NodeFilter.all => true,
        // "Fast" means measured and under the amber threshold.
        _NodeFilter.fast => node.latencyMs != null &&
            node.latencyMs! >= 0 &&
            node.latencyMs! < 260,
        _NodeFilter.favorites => node.favorite,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final state = widget.state;
    final nodes = _visible;
    final grouped = <String?, List<ProxyNode>>{};
    for (final node in nodes) {
      grouped.putIfAbsent(node.subscriptionId, () => []).add(node);
    }

    return PageFrame(
      title: l10n.nodesTitle,
      subtitle: state.nodes.isEmpty
          ? l10n.nodesNothingImported
          : l10n.nodesSubtitle(state.nodes.length, state.subscriptions.length),
      trailing: Row(
        children: [
          IconButton(
            onPressed: state.nodes.isEmpty || state.isTestingLatency
                ? null
                : state.testLatency,
            tooltip: l10n.actionTestLatency,
            icon: state.isTestingLatency
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.speed_outlined, color: palette.muted),
          ),
          IconButton(
            onPressed: () => showImportSheet(context, state),
            tooltip: l10n.actionImport,
            icon: Icon(Icons.add, color: palette.muted),
          ),
        ],
      ),
      children: [
        if (state.nodes.isEmpty)
          EmptyState(
            icon: Icons.hub_outlined,
            title: l10n.homeNoNodesYet,
            message: l10n.nodesImportBody,
            action: FilledButton.icon(
              onPressed: () => showImportSheet(context, state),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.nodesImportTitle),
            ),
          )
        else ...[
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: l10n.nodesSearch,
              prefixIcon: Icon(Icons.search, size: 20, color: palette.faint),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              for (final filter in _NodeFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: Gap.sm),
                  child: ChoiceChip(
                    label: Text(_filterLabel(l10n, filter)),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                    backgroundColor: palette.surface,
                    selectedColor: palette.violet.withValues(alpha: .22),
                    side: BorderSide(
                      color: _filter == filter
                          ? palette.violet.withValues(alpha: .55)
                          : palette.border,
                    ),
                    labelStyle: TextStyle(
                      color: _filter == filter
                          ? palette.violetSoft
                          : palette.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          for (final subscription in state.subscriptions)
            _SubscriptionSection(
              state: state,
              subscription: subscription,
              nodes: grouped[subscription.id] ?? const [],
            ),
          if (grouped.containsKey(null)) ...[
            SectionLabel(l10n.nodesGroupManual),
            for (final node in grouped[null]!)
              _NodeRow(state: state, node: node),
            const SizedBox(height: 22),
          ],
          if (nodes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: EmptyState(
                icon: Icons.search_off_outlined,
                title: l10n.nodesNoMatches,
                message: l10n.nodesNoMatchesBody,
              ),
            ),
        ],
      ],
    );
  }
}

class _SubscriptionSection extends StatelessWidget {
  const _SubscriptionSection({
    required this.state,
    required this.subscription,
    required this.nodes,
  });

  final AppState state;
  final Subscription subscription;
  final List<ProxyNode> nodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final refreshing = state.isRefreshing(subscription.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          padding: const EdgeInsets.all(14),
          accent: subscription.lastError != null ? palette.amber : null,
          child: Row(
            children: [
              Icon(
                switch (subscription.kind) {
                  SubscriptionKind.remote => Icons.cloud_outlined,
                  SubscriptionKind.config => Icons.description_outlined,
                  SubscriptionKind.manual => Icons.link,
                },
                size: 18,
                color: palette.violetSoft,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subscription.lastError ?? _subtitle(l10n, subscription),
                      // Three facts joined by separators do not fit one mobile
                      // line, and clipping mid-number ("· 123 …") loses the one
                      // part a reader is checking. Wrapping keeps all three.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subscription.lastError != null
                            ? palette.amber
                            : palette.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (subscription.isRemote)
                IconButton(
                  onPressed: refreshing
                      ? null
                      : () => state.refreshSubscription(subscription.id),
                  tooltip: l10n.actionUpdate,
                  icon: refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
              IconButton(
                onPressed: () => _confirmRemove(context),
                tooltip: l10n.actionRemove,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: palette.faint,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        for (final node in nodes) _NodeRow(state: state, node: node),
        const SizedBox(height: 22),
      ],
    );
  }

  static String _subtitle(L10n l10n, Subscription subscription) {
    final parts = <String>[l10n.nodesCountLabel(subscription.nodeCount)];
    if (subscription.updatedAt != null) {
      parts.add(l10n.nodesUpdatedAgo(_ago(l10n, subscription.updatedAt!)));
    }
    if (subscription.expiresAt != null) {
      final days = subscription.expiresAt!.difference(DateTime.now()).inDays;
      parts.add(days >= 0 ? l10n.nodesDaysLeft(days) : l10n.nodesExpired);
    }
    return parts.join(' · ');
  }

  static String _ago(L10n l10n, DateTime time) {
    final delta = DateTime.now().difference(time);
    if (delta.inMinutes < 1) return l10n.agoJustNow;
    if (delta.inHours < 1) return l10n.agoMinutes(delta.inMinutes);
    if (delta.inDays < 1) return l10n.agoHours(delta.inHours);
    return l10n.agoDays(delta.inDays);
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final l10n = L10n.of(context);
    final danger = context.palette.danger;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.nodesRemoveSource),
        content: Text(
          l10n.nodesRemoveSourceBody(subscription.name, subscription.nodeCount),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: danger),
            child: Text(l10n.actionRemove),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.removeSubscription(subscription.id);
    }
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.state, required this.node});

  final AppState state;
  final ProxyNode node;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final selected = state.selectedNodeId == node.id;
    final color = latencyColor(palette, node.latencyMs);
    final region = node.regionCode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => state.selectNode(node),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? palette.violet.withValues(alpha: .10)
                  : palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: selected
                    ? palette.violet.withValues(alpha: .65)
                    : palette.border,
              ),
            ),
            child: Row(
              children: [
                // The region code replaces the generic server icon when the name
                // gives one away; nodes whose region we cannot read keep the
                // icon rather than showing a guess.
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tintFill(color),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: region == null
                      ? Icon(Icons.dns_outlined, color: color, size: 18)
                      : Text(
                          region,
                          style: monoStyle(
                            size: 13,
                            color: color,
                            weight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _ProtocolTag(label: node.protocol.label),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(
                              node.server,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: monoStyle(size: 10, color: palette.faint),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Text(
                  switch (node.latencyMs) {
                    null => l10n.latencyUnknown,
                    < 0 => l10n.latencyFail,
                    final value => '$value',
                  },
                  style: monoStyle(color: color, weight: FontWeight.w600),
                ),
                if (node.isTested && !node.isUnreachable)
                  Text(' ms', style: monoStyle(size: 9, color: color)),
                const SizedBox(width: Gap.xs),
                IconButton(
                  onPressed: () => state.toggleFavorite(node.id),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    node.favorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 19,
                    color: node.favorite ? palette.amber : palette.faint,
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: palette.violetSoft, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Protocol name as a small outlined tag.
///
/// Neutral on purpose: the row already spends colour on latency, and giving each
/// protocol its own hue would compete with the reading that actually guides a
/// choice between nodes.
class _ProtocolTag extends StatelessWidget {
  const _ProtocolTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label.toUpperCase(),
        style:
            monoStyle(size: 9, color: palette.muted, weight: FontWeight.w600),
      ),
    );
  }
}
