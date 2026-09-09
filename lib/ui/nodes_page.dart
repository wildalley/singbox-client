/// Node list: search, filter, per-subscription grouping, and selection.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../models/node_sort.dart';
import '../models/subscription.dart';
import '../state/app_state.dart';
import 'clock.dart';
import 'import_sheet.dart';
import 'notice_text.dart';
import 'theme.dart';
import 'widgets.dart';

enum _NodeFilter { all, fast, favorites }

String _filterLabel(L10n l10n, _NodeFilter filter) => switch (filter) {
      _NodeFilter.all => l10n.nodesFilterAll,
      _NodeFilter.fast => l10n.nodesFilterFast,
      _NodeFilter.favorites => l10n.nodesFilterFavorites,
    };

/// The manually-added group, as a source id. Its nodes carry no
/// `subscriptionId`, and `null` is already taken to mean every source.
const _manualSource = '';

class NodesPage extends StatefulWidget {
  const NodesPage({super.key, required this.state});

  final AppState state;

  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage> {
  final _searchController = TextEditingController();
  final _contextCollapsedSources = <String>{};
  var _query = '';
  var _filter = _NodeFilter.all;

  /// Selected source, or null for all of them.
  String? _source;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// A search or source filter temporarily reveals a folded section so a match
  /// cannot look missing. If the user taps that section's header while it is
  /// revealed, remember the explicit close locally; otherwise the forced-open
  /// condition would immediately undo the tap on the next build.
  void _toggleSource(String sourceId) {
    final contextual = _query.trim().isNotEmpty || _source == sourceId;
    if (contextual) {
      // This is a temporary reveal caused by the active search/source filter;
      // do not overwrite the user's persisted fold preference just because the
      // filter is on.
      setState(() {
        if (!_contextCollapsedSources.add(sourceId)) {
          _contextCollapsedSources.remove(sourceId);
        }
      });
    } else {
      widget.state.toggleSourceCollapsed(sourceId);
    }
  }

  void _setQuery(String query) {
    if (_query == query) return;
    setState(() {
      _query = query;
      _contextCollapsedSources.clear();
    });
  }

  void _setSource(String? source) {
    if (_source == source) return;
    setState(() {
      _source = source;
      _contextCollapsedSources.clear();
    });
  }

  List<ProxyNode> _visible(String? source) {
    final query = _query.trim().toLowerCase();
    return widget.state.nodes.where((node) {
      if (source != null && (node.subscriptionId ?? _manualSource) != source) {
        return false;
      }
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
  Widget build(BuildContext context) =>
      PageBody(state: widget.state, builder: _build);

  Widget _build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final state = widget.state;

    // Every source that exists, in the order its section renders — from all of
    // the nodes, not the filtered ones, so the row does not reshuffle under the
    // finger while a search narrows the list.
    final sources = <String?>[
      for (final subscription in state.subscriptions) subscription.id,
      if (state.nodes.any((node) => node.subscriptionId == null)) _manualSource,
    ];
    // A source can be removed while it is the selected one.
    final source = sources.contains(_source) ? _source : null;

    final nodes = _visible(source);
    final grouped = <String?, List<ProxyNode>>{};
    for (final node in nodes) {
      grouped.putIfAbsent(node.subscriptionId, () => []).add(node);
    }
    // Within a source, never across them: the sections are the user's own
    // grouping, and a global order would have to dissolve them to mean anything.
    for (final key in grouped.keys.toList()) {
      grouped[key] = sortNodes(grouped[key]!, state.nodeSort);
    }

    // A folded source still shows what a search turned up inside it: a match
    // hidden behind a chevron reads as "no results", not as folded. Picking a
    // source from the row above is the same kind of request, so it unfolds too —
    // in both cases without touching what the user folded.
    // An explicit close wins over the temporary reveal, including sources
    // whose persisted preference was already open before the filter changed.
    bool expanded(String sourceId) =>
        _query.trim().isNotEmpty || source == sourceId
            ? !_contextCollapsedSources.contains(sourceId)
            : !state.isSourceCollapsed(sourceId);

    return PageFrame(
      title: l10n.nodesTitle,
      subtitle: state.nodes.isEmpty
          ? l10n.nodesNothingImported
          : l10n.nodesSubtitle(state.nodes.length, state.subscriptions.length),
      trailing: Row(
        children: [
          // Left of the probe button, because it reads the figures that one
          // writes. Tinted while latency order is on, so a list the user asked
          // to be reordered says so without scrolling to check.
          IconButton(
            onPressed: state.nodes.isEmpty
                ? null
                : () => state.setNodeSort(
                      state.nodeSort == NodeSort.latency
                          ? NodeSort.source
                          : NodeSort.latency,
                    ),
            tooltip: state.nodeSort == NodeSort.latency
                ? l10n.nodesSortSource
                : l10n.nodesSortLatency,
            // One glyph, two colours: `sort` has no distinct outlined and filled
            // forms to lean on, so the tint carries the state on its own.
            icon: Icon(
              Icons.sort_rounded,
              color: state.nodeSort == NodeSort.latency
                  ? palette.violetSoft
                  : palette.muted,
            ),
          ),
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
            onChanged: _setQuery,
            decoration: InputDecoration(
              hintText: l10n.nodesSearch,
              prefixIcon: Icon(Icons.search, size: 20, color: palette.faint),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _setQuery('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              for (final filter in _NodeFilter.values)
                _ChoiceChipCell(
                  label: _filterLabel(l10n, filter),
                  selected: _filter == filter,
                  onSelected: () => setState(() => _filter = filter),
                ),
            ],
          ),
          // One source needs no picker, and the row would only take height from
          // the list.
          if (sources.length > 1) ...[
            const SizedBox(height: Gap.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ChoiceChipCell(
                    label: l10n.nodesSourceAll,
                    selected: source == null,
                    onSelected: () => _setSource(null),
                  ),
                  for (final id in sources)
                    _ChoiceChipCell(
                      label: id == _manualSource
                          ? l10n.nodesGroupManual
                          : state.subscriptions
                              .firstWhere((item) => item.id == id)
                              .name,
                      selected: source == id,
                      onSelected: () => _setSource(id),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          // Above every source, because it belongs to none of them: the engine
          // chooses across all the nodes at once. That is also why it goes away
          // as soon as the list is narrowed — by a search, a filter, or one
          // source — since anything left standing at the top of those results
          // reads as part of them.
          if (_query.trim().isEmpty &&
              _filter == _NodeFilter.all &&
              source == null) ...[
            _AutoRow(state: state),
            const SizedBox(height: 18),
          ],
          for (final subscription in state.subscriptions)
            if (source == null || source == subscription.id)
              _SubscriptionSection(
                state: state,
                subscription: subscription,
                nodes: grouped[subscription.id] ?? const [],
                collapsed: !expanded(subscription.id),
                onToggle: () => _toggleSource(subscription.id),
              ),
          if (grouped.containsKey(null) &&
              (source == null || source == _manualSource)) ...[
            // A section label is one small line high, which is too thin a
            // target on a phone, so the fold takes a little padding of its own.
            InkWell(
              onTap: () => _toggleSource(_manualSource),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                child: SectionLabel(
                  l10n.nodesGroupManual,
                  trailing: _FoldChevron(collapsed: !expanded(_manualSource)),
                ),
              ),
            ),
            if (expanded(_manualSource)) ..._nodeRows(state, grouped[null]!),
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

/// One chip in the filter or source row.
///
/// Extracted so the two rows cannot drift apart: they are the same control at
/// the same size, and only the axis they select on differs.
class _ChoiceChipCell extends StatelessWidget {
  const _ChoiceChipCell({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: Gap.sm),
      child: ChoiceChip(
        // A source is named by the user or by the panel, so it can be long.
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 148),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        selected: selected,
        onSelected: (_) => onSelected(),
        backgroundColor: palette.surface,
        selectedColor: palette.violet.withValues(alpha: .22),
        side: BorderSide(
          color:
              selected ? palette.violet.withValues(alpha: .55) : palette.border,
        ),
        labelStyle: TextStyle(
          color: selected ? palette.violetSoft : palette.muted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        showCheckmark: false,
      ),
    );
  }
}

class _SubscriptionSection extends StatelessWidget {
  const _SubscriptionSection({
    required this.state,
    required this.subscription,
    required this.nodes,
    required this.collapsed,
    required this.onToggle,
  });

  final AppState state;
  final Subscription subscription;
  final List<ProxyNode> nodes;

  /// Folded away: the header stays, its rows do not.
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final refreshing = state.isRefreshing(subscription.id);
    final failure = subscription.lastFailure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          padding: const EdgeInsets.all(14),
          accent: failure != null ? palette.amber : null,
          onTap: onToggle,
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
                      failure == null
                          ? _subtitle(l10n, subscription)
                          : subscriptionFailureText(
                              l10n,
                              failure,
                              status: subscription.lastFailureStatus,
                            ),
                      // Three facts joined by separators do not fit one mobile
                      // line, and clipping mid-number ("· 123 …") loses the one
                      // part a reader is checking. Wrapping keeps all three.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: failure != null ? palette.amber : palette.muted,
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
              // No hit area of its own: the two buttons beside it already take
              // theirs out of the panel, and a third would push the name in
              // further for something the whole header does.
              _FoldChevron(collapsed: collapsed),
            ],
          ),
        ),
        if (!collapsed) ...[
          const SizedBox(height: Gap.md),
          ..._nodeRows(state, nodes),
        ],
        const SizedBox(height: 22),
      ],
    );
  }

  static String _subtitle(L10n l10n, Subscription subscription) {
    final parts = <String>[l10n.nodesCountLabel(subscription.nodeCount)];
    if (subscription.updatedAt != null) {
      parts.add(
          l10n.nodesUpdatedAgo(relativeTime(l10n, subscription.updatedAt!)));
    }
    if (subscription.expiresAt != null) {
      final days = subscription.expiresAt!.difference(clockNow()).inDays;
      parts.add(days >= 0 ? l10n.nodesDaysLeft(days) : l10n.nodesExpired);
    }
    return parts.join(' · ');
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

/// The fold affordance on a source header: down when open, left when folded.
class _FoldChevron extends StatelessWidget {
  const _FoldChevron({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      // Right when folded, down when open: the disclosure convention, and the
      // quarter turn is what makes the two states read as one control.
      turns: collapsed ? -0.25 : 0,
      duration: Motion.fast,
      child: Icon(
        Icons.expand_more,
        size: 18,
        color: context.palette.faint,
      ),
    );
  }
}

/// The `urltest` group as a row: the engine measures and picks, not the user.
///
/// Shaped like a [_NodeRow] and selected the same way, because it competes with
/// the nodes for the same choice. It carries no latency figure — which node the
/// group settled on is inside the engine, and printing this device's TCP handshake
/// beside it would be a number for something else.
class _AutoRow extends StatelessWidget {
  const _AutoRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final selected = state.isAutoSelected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Panel(
        onTap: state.selectAuto,
        selected: selected,
        accent: selected ? palette.violet : null,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tintFill(palette.violetSoft),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: palette.violetSoft,
                size: 19,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.nodesAuto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    l10n.nodesAutoBody,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: Gap.sm),
              Icon(Icons.check_rounded, size: 18, color: palette.violetSoft),
            ],
          ],
        ),
      ),
    );
  }
}

/// Endpoint IDs are stable across refreshes, but a source can publish the same
/// endpoint under multiple names, or repeat an entry verbatim. Each row needs
/// its own key: duplicate keys can orphan painted rows when a section folds.
/// Include the name to keep aliases stable when sorting/filtering, then count
/// identical copies so even repeated names remain distinct. The endpoint ID
/// used for proxy selection and persisted data stays untouched.
Iterable<Widget> _nodeRows(AppState state, List<ProxyNode> nodes) sync* {
  final occurrences = <(String?, String, String), int>{};
  for (final node in nodes) {
    final identity = (node.subscriptionId, node.id, node.name);
    final occurrence =
        occurrences.update(identity, (n) => n + 1, ifAbsent: () => 0);
    yield _NodeRow(
      key: ValueKey((identity, occurrence)),
      state: state,
      node: node,
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({super.key, required this.state, required this.node});

  final AppState state;
  final ProxyNode node;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final selected = state.selectedNodeId == node.id;
    final color = latencyColor(palette, node.latencyMs);
    final region = node.regionCode;

    // The list re-sorts under the user when a latency sweep lands, so the row
    // slides from its old place rather than appearing in its new one.
    return ReorderSlide(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Panel(
          onTap: () => state.selectNode(node),
          selected: selected,
          accent: selected ? palette.violet : null,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // The region code replaces the generic server icon when the name
              // gives one away; nodes whose region we cannot read keep the icon
              // rather than showing a guess.
              AnimatedContainer(
                duration: motionOf(context, Motion.normal),
                curve: Motion.curve,
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
              // A sweep turns every reading at once. Fading the colour instead of
              // cutting it keeps a screen of rows from flickering as a block.
              AnimatedDefaultTextStyle(
                duration: motionOf(context, Motion.normal),
                curve: Motion.curve,
                // Merged onto the ambient style, not handed over whole: this
                // widget replaces the subtree's default where a style passed to a
                // Text merges into it, and dropping the inherited line height
                // moves the reading a couple of pixels.
                style: DefaultTextStyle.of(context).style.merge(
                      monoStyle(color: color, weight: FontWeight.w600),
                    ),
                child: Text(
                  switch (node.latencyMs) {
                    null => l10n.latencyUnknown,
                    < 0 => l10n.latencyFail,
                    final value => '$value',
                  },
                ),
              ),
              if (node.isTested && !node.isUnreachable)
                AnimatedDefaultTextStyle(
                  duration: motionOf(context, Motion.normal),
                  curve: Motion.curve,
                  style: DefaultTextStyle.of(context)
                      .style
                      .merge(monoStyle(size: 9, color: color)),
                  child: const Text(' ms'),
                ),
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
              IconButton(
                tooltip: l10n.nodesChain,
                onPressed: () => _showChainSheet(context, state, node),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  node.detourNodeId == null
                      ? Icons.link_outlined
                      : Icons.link_rounded,
                  size: 19,
                  color: node.detourNodeId == null
                      ? palette.faint
                      : palette.violetSoft,
                ),
              ),
              // Eases the width open instead of reserving a slot on every row:
              // at rest this is exactly the old layout — the mark on the selected
              // row, nothing on the others — and only the change is animated.
              AnimatedSize(
                duration: motionOf(context, Motion.fast),
                curve: Motion.curve,
                child: selected
                    ? Icon(
                        Icons.check_circle,
                        color: palette.violetSoft,
                        size: 18,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showChainSheet(
  BuildContext context,
  AppState state,
  ProxyNode node,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      minChildSize: .45,
      maxChildSize: .92,
      builder: (context, scrollController) => _ChainSheet(
        state: state,
        node: node,
        scrollController: scrollController,
      ),
    ),
  );
}

class _ChainSheet extends StatefulWidget {
  const _ChainSheet({
    required this.state,
    required this.node,
    required this.scrollController,
  });

  final AppState state;
  final ProxyNode node;
  final ScrollController scrollController;

  @override
  State<_ChainSheet> createState() => _ChainSheetState();
}

class _ChainSheetState extends State<_ChainSheet> {
  late String? _detourNodeId = widget.node.detourNodeId;
  var _saving = false;

  List<ProxyNode> get _candidates => [
        for (final candidate in widget.state.nodes)
          if (candidate.id != widget.node.id &&
              !wouldCreateDetourCycle(
                widget.state.nodes,
                widget.node.id,
                candidate.id,
              ))
            candidate,
      ];

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.state.setNodeDetour(widget.node.id, _detourNodeId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final candidates = _candidates;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.sm, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.nodesChain,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        l10n.nodesChainBody,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.actionCancel,
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.sm),
            child: Panel(
              selected: _detourNodeId == null,
              accent: _detourNodeId == null ? palette.violet : null,
              onTap:
                  _saving ? null : () => setState(() => _detourNodeId = null),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.link_off_rounded, color: palette.muted),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.nodesChainDirect,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.nodesChainDirectBody,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (_detourNodeId == null)
                    Icon(Icons.check_rounded, color: palette.violetSoft),
                ],
              ),
            ),
          ),
          Expanded(
            child: candidates.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.xl),
                      child: Text(
                        l10n.nodesChainNoCandidates,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(
                        Gap.xl, Gap.sm, Gap.xl, Gap.xl),
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Gap.sm),
                    itemBuilder: (context, index) {
                      final candidate = candidates[index];
                      final selected = _detourNodeId == candidate.id;
                      return Panel(
                        selected: selected,
                        accent: selected ? palette.violet : null,
                        onTap: _saving
                            ? null
                            : () => setState(
                                  () => _detourNodeId = candidate.id,
                                ),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.dns_outlined, color: palette.violetSoft),
                            const SizedBox(width: Gap.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    candidate.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${candidate.protocol.label} · ${candidate.server}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: monoStyle(
                                      size: 10,
                                      color: palette.faint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Icon(Icons.check_rounded,
                                  color: palette.violetSoft),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.md),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.actionSave),
              ),
            ),
          ),
        ],
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
