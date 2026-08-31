/// Central app state: nodes, subscriptions, settings, and the proxy runtime.
///
/// Everything the UI reads goes through this [ChangeNotifier]. It owns
/// persistence and the [ProxyController] lifecycle so screens stay stateless.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/config_builder.dart';
import '../data/importer.dart';
import '../data/latency_tester.dart';
import '../data/rule_set_updater.dart';
import '../data/rule_sets.dart';
import '../data/storage.dart';
import '../models/app_settings.dart';
import '../models/node.dart';
import '../models/node_sort.dart';
import '../models/proxy_state.dart';
import '../models/subscription.dart';
import '../platform/proxy_controller.dart';

/// What a notice is about. The UI turns this into localized text; this layer
/// never builds user-facing sentences, so it needs no [BuildContext].
enum NoticeKind {
  needNodes,
  permissionDenied,
  switchFailed,
  reloadFailed,
  noUrlToRefresh,
  subscriptionUpdated,
  nodesImported,

  /// An import or refresh that produced no nodes. The reason travels as
  /// [AppNotice.failure] rather than as a sentence.
  importFailed,
  ruleSetsUpdated,
  ruleSetsUpdateFailed,
  ruleSetsUnavailable,

  /// Text that is already final: an engine error or a redacted exception.
  /// Not translatable, so it is passed through as-is.
  passthrough,
}

/// A transient message for the UI to surface in a snackbar.
class AppNotice {
  const AppNotice(
    this.kind, {
    this.isError = false,
    this.detail,
    this.name,
    this.count,
    this.skipped,
    this.failure,
  });

  const AppNotice.error(NoticeKind kind, {String? detail})
      : this(kind, isError: true, detail: detail);

  /// Already-final text, e.g. a redacted exception message.
  const AppNotice.passthrough(String text, {bool isError = true})
      : this(NoticeKind.passthrough, isError: isError, detail: text);

  final NoticeKind kind;
  final bool isError;

  /// Error detail or passthrough text.
  final String? detail;

  /// Subscription name, for the kinds that mention one.
  final String? name;

  /// A count of nodes, or the HTTP status for [NoticeKind.importFailed].
  final int? count;
  final int? skipped;

  /// Why an import failed, for [NoticeKind.importFailed].
  final SubscriptionFailure? failure;
}

class AppState extends ChangeNotifier {
  AppState({
    required Storage storage,
    required ProxyController controller,
    Importer? importer,
    LatencyTester? latencyTester,
    RuleSetUpdater? ruleSetUpdater,
    String? ruleSetDir,
    Duration? urlTestTimeout,
  })  : _urlTestTimeout = urlTestTimeout ?? _defaultUrlTestTimeout,
        _storage = storage,
        _controller = controller,
        _importer = importer ?? Importer(),
        _latencyTester = latencyTester ?? const LatencyTester(),
        _ruleSetUpdater = ruleSetUpdater ?? RuleSetUpdater(),
        _ruleSetDir = ruleSetDir {
    _nodes = _storage.readNodes();
    _subscriptions = _storage.readSubscriptions();
    _settings = _storage.readSettings();
    _selectedNodeId = _storage.readSelectedNodeId();
    _collapsedSources = {..._storage.readCollapsedSources()};
    _nodeSort = _storage.readNodeSort();
    _proxyState = _controller.currentState;

    // Read synchronously so the very first `_buildConfig()` already carries it;
    // a first run generates one and persists it in the background, which the
    // in-memory prefs cache makes readable again immediately.
    final storedSecret = _storage.readClashSecret();
    _clashSecret = storedSecret ?? _newClashSecret();
    if (storedSecret == null) _storage.writeClashSecret(_clashSecret);

    _stateSub = _controller.states.listen(_onProxyState);
    _trafficSub = _controller.traffic.listen((value) {
      _traffic = value;
      _pushHistory(value);
      notifyListeners();
    });
    _logSub = _controller.logs.listen((entry) {
      _logs.add(entry);
      if (_logs.length > _maxLogs) {
        _logs.removeRange(0, _logs.length - _maxLogs);
      }
      notifyListeners();
    });

    // Shown in Settings; failure just leaves the row as unknown.
    _controller.coreVersion().then((value) {
      _coreVersion = value;
      notifyListeners();
    }, onError: (_) {});

    _readRuleSetInstall();
  }

  /// Stored in the selected-node key to mean "let the engine choose".
  ///
  /// A sentinel rather than a second stored flag, because the two are the same
  /// decision: one exit is in effect at a time, so one key holds it and there is
  /// no state where both are set. No node id can collide with it — ids are
  /// base-36 timestamps or subscription-derived, never bracketed.
  static const autoSelection = '[auto]';

  static const _maxLogs = 500;

  /// 60 samples at roughly one per second — the rolling window the design plan
  /// asks for before any figure is compared against an earlier period.
  static const _historyLength = 60;

  final Storage _storage;
  final ProxyController _controller;
  final Importer _importer;
  final LatencyTester _latencyTester;
  final RuleSetUpdater _ruleSetUpdater;

  /// Where the bundled `.srs` rule-sets were unpacked, or null if they are not
  /// on disk — see [ConfigBuilder.build].
  final String? _ruleSetDir;

  /// How old a downloaded list may get before a connect refreshes it. Country
  /// and ad-domain lists move slowly; this is about not shipping a year-old copy,
  /// not about being current to the day.
  static const _ruleSetMaxAge = Duration(days: 7);

  /// How old a subscription may get before a connect re-fetches it. Panels
  /// rotate nodes and hand out new ones on a timescale of days, so half a day is
  /// about catching up after a break rather than polling.
  static const _subscriptionMaxAge = Duration(hours: 12);

  late List<ProxyNode> _nodes;
  late List<Subscription> _subscriptions;
  late AppSettings _settings;
  String? _selectedNodeId;

  /// Bearer token for the config's Clash API listener. Never surfaced in the UI,
  /// a notice, or a log line.
  late String _clashSecret;

  var _proxyState = ProxyState.disconnected;
  var _traffic = ProxyTraffic.zero;
  final _logs = <ProxyLogEntry>[];

  /// Rolling per-sample history for the charts, oldest first. Lives here rather
  /// than in the home page's State so switching tabs doesn't blank the charts.
  final _downlinkHistory = <int>[];
  final _uplinkHistory = <int>[];
  final _connectionHistory = <int>[];
  final _memoryHistory = <int>[];

  StreamSubscription<ProxyState>? _stateSub;
  StreamSubscription<ProxyTraffic>? _trafficSub;
  StreamSubscription<ProxyLogEntry>? _logSub;

  var _busy = false;
  var _testingLatency = false;
  final _refreshing = <String>{};
  AppNotice? _notice;

  /// Sources the user folded away on the nodes page, by source id.
  late Set<String> _collapsedSources;

  /// How the nodes page orders rows within a source.
  ///
  /// Here rather than in [AppSettings] because it is a view preference, not a
  /// tunnel one: `applySettings` reloads a running config, and reordering a list
  /// must never drop the connection.
  late NodeSort _nodeSort;

  /// What the rule-sets on disk are, or null on a platform that has none.
  RuleSetInstall? _ruleSetInstall;
  var _updatingRuleSets = false;

  /// One automatic attempt per app run: a silent retry on every connect would
  /// hammer an upstream that is simply unreachable from here.
  var _autoUpdateTried = false;

  /// The same rule for the subscriptions, tracked separately so one upstream
  /// being down does not stop the other from ever being tried.
  var _autoRefreshTried = false;

  /// sing-box core version reported by the platform, null until it answers.
  String? _coreVersion;

  // ------------------------------------------------------------------ reads

  List<ProxyNode> get nodes => List.unmodifiable(_nodes);
  List<Subscription> get subscriptions => List.unmodifiable(_subscriptions);
  String? get coreVersion => _coreVersion;
  AppSettings get settings => _settings;
  ProxyState get proxyState => _proxyState;
  ProxyTraffic get traffic => _traffic;
  List<ProxyLogEntry> get logs => List.unmodifiable(_logs);

  /// Chart series, oldest sample first. Copies: the painters diff the old and
  /// new lists, and handing out the same instance would always look unchanged.
  List<int> get downlinkHistory => List.of(_downlinkHistory);
  List<int> get uplinkHistory => List.of(_uplinkHistory);
  List<int> get connectionHistory => List.of(_connectionHistory);
  List<int> get memoryHistory => List.of(_memoryHistory);

  bool get isConnected => _proxyState.isConnected;
  bool get isBusy => _busy || _proxyState.stage.isBusy;
  bool get isTestingLatency => _testingLatency;

  /// The rule-sets on disk: when they were written and whether a download has
  /// replaced the shipped copies. Null where they were never unpacked, which is
  /// also where [updateRuleSets] has nothing to write to.
  RuleSetInstall? get ruleSetInstall => _ruleSetInstall;

  bool get hasLocalRuleSets => _ruleSetDir != null;
  bool get isUpdatingRuleSets => _updatingRuleSets;

  bool isRefreshing(String subscriptionId) =>
      _refreshing.contains(subscriptionId);

  /// Whether the nodes page should render [sourceId]'s rows folded away.
  bool isSourceCollapsed(String sourceId) =>
      _collapsedSources.contains(sourceId);

  NodeSort get nodeSort => _nodeSort;

  String? get selectedNodeId => _selectedNodeId;

  /// Whether the engine picks the exit itself.
  ///
  /// False with no nodes: there is nothing for `urltest` to choose between, and
  /// the config's selector falls back to direct anyway.
  bool get isAutoSelected =>
      _selectedNodeId == autoSelection && _nodes.isNotEmpty;

  /// The node the user pinned, or null when the engine chooses.
  ///
  /// Null under [isAutoSelected] is what makes the rest of the app work without
  /// a second code path: [_buildConfig] passes no `selectedNodeId`, so the
  /// selector defaults to [ConfigTags.auto], and every screen that reads this
  /// already handles null.
  ProxyNode? get selectedNode {
    if (_nodes.isEmpty || isAutoSelected) return null;
    for (final node in _nodes) {
      if (node.id == _selectedNodeId) return node;
    }
    return _nodes.first;
  }

  /// Pending notice, consumed by the UI so it shows exactly once.
  AppNotice? takeNotice() {
    final value = _notice;
    _notice = null;
    return value;
  }

  /// Nodes grouped by subscription id (`null` key = manually added).
  Map<String?, List<ProxyNode>> get nodesBySubscription {
    final grouped = <String?, List<ProxyNode>>{};
    for (final node in _nodes) {
      grouped.putIfAbsent(node.subscriptionId, () => []).add(node);
    }
    return grouped;
  }

  // ------------------------------------------------------------- connection

  /// Connects, or reconnects with the current config if already running.
  Future<void> connect() async {
    if (_nodes.isEmpty) {
      _notify(const AppNotice.error(NoticeKind.needNodes));
      return;
    }

    _busy = true;
    notifyListeners();
    try {
      final granted = await _controller.requestPermission();
      if (!granted) {
        _notify(const AppNotice.error(NoticeKind.permissionDenied));
        return;
      }
      await _controller.start(_renderConfig());
    } on Object catch (error) {
      _fail(_short(error));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _busy = true;
    notifyListeners();
    try {
      await _controller.stop();
    } on Object catch (error) {
      _fail(_short(error));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> toggleConnection() => isConnected ? disconnect() : connect();

  /// Selects [node]. While connected this switches the live selector outbound
  /// instead of restarting the tunnel.
  Future<void> selectNode(ProxyNode node) =>
      _select(node.id, ConfigBuilder.outboundTag(node));

  /// Hands the choice of exit to the engine's `urltest` group.
  ///
  /// The group is already in every config with nodes, measuring its members on
  /// its own interval, so this only has to point the selector at it.
  Future<void> selectAuto() => _select(autoSelection, ConfigTags.auto);

  /// Records a selection and, while connected, moves the live selector to it.
  Future<void> _select(String id, String outboundTag) async {
    _selectedNodeId = id;
    await _storage.writeSelectedNodeId(id);
    notifyListeners();

    if (!isConnected) return;
    try {
      await _controller.selectOutbound(outboundTag);
    } on Object catch (error) {
      _notify(AppNotice.error(NoticeKind.switchFailed, detail: _short(error)));
    }
  }

  /// Re-renders the config and applies it to a running tunnel.
  Future<void> applySettings(AppSettings settings) async {
    _settings = settings;
    await _storage.writeSettings(settings);
    notifyListeners();

    if (!isConnected) return;
    try {
      await _controller.reload(_renderConfig());
    } on Object catch (error) {
      _notify(AppNotice.error(NoticeKind.reloadFailed, detail: _short(error)));
    }
  }

  // ------------------------------------------------------------------ import

  /// Imports pasted text: subscription URL, share links, or sing-box JSON.
  Future<void> importFromText(String text, {String? name}) async {
    _busy = true;
    notifyListeners();
    try {
      final trimmed = text.trim();
      final isUrl =
          trimmed.startsWith('http://') || trimmed.startsWith('https://');
      final subscription = Subscription(
        id: _newId(),
        name: name?.trim().isNotEmpty == true ? name!.trim() : 'Imported',
        kind: isUrl ? SubscriptionKind.remote : SubscriptionKind.manual,
        url: isUrl ? trimmed : null,
      );

      final result = await _importer.importText(
        trimmed,
        subscriptionId: subscription.id,
        viaLocalProxy: isConnected,
      );
      _absorb(subscription, result);
    } on Object catch (error) {
      _notify(_importFailure(error));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Imports a sing-box config or link list from a file on disk.
  Future<void> importFromFile(String path, {String? name}) async {
    _busy = true;
    notifyListeners();
    try {
      final subscription = Subscription(
        id: _newId(),
        name: name?.trim().isNotEmpty == true
            ? name!.trim()
            : path.split('/').last,
        kind: SubscriptionKind.config,
      );
      final result = await _importer.importFile(
        path,
        subscriptionId: subscription.id,
      );
      _absorb(subscription, result);
    } on Object catch (error) {
      _notify(_importFailure(error));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Re-fetches a remote subscription, replacing only its own nodes.
  ///
  /// [silent] suppresses the notices, for the automatic refresh on connect: the
  /// user did not ask for it, so it has no business interrupting them. A failure
  /// is still recorded on the subscription, which is where they would look.
  Future<void> refreshSubscription(
    String subscriptionId, {
    bool silent = false,
  }) async {
    // The automatic refresh on connect and a user's tap on the same row can
    // land together; the second would replace this source's nodes twice from
    // two fetches, and the later answer is not necessarily the newer one.
    if (_refreshing.contains(subscriptionId)) return;
    final index =
        _subscriptions.indexWhere((item) => item.id == subscriptionId);
    if (index < 0) return;
    final subscription = _subscriptions[index];
    if (!subscription.isRemote) {
      if (!silent) {
        _notify(AppNotice(
          NoticeKind.noUrlToRefresh,
          isError: true,
          name: subscription.name,
        ));
      }
      return;
    }

    _refreshing.add(subscriptionId);
    notifyListeners();
    try {
      final result = await _importer.refresh(
        subscription,
        // Connected, the tunnel is tried first: a panel this user cannot reach
        // directly is only reachable through the config's loopback inbound,
        // because the app itself is excluded from the VPN.
        viaLocalProxy: isConnected,
      );
      // Carry latency and favourites across the refresh.
      final previous = {
        for (final node in _nodes)
          if (node.subscriptionId == subscriptionId) node.id: node,
      };
      final merged = result.nodes
          .map((node) => switch (previous[node.id]) {
                final ProxyNode old => node.copyWith(
                    latencyMs: old.latencyMs,
                    favorite: old.favorite,
                  ),
                null => node,
              })
          .toList();

      _nodes = [
        for (final node in _nodes)
          if (node.subscriptionId != subscriptionId) node,
        ...merged,
      ];
      _subscriptions = [..._subscriptions]..[index] = result.subscription;
      await _persistNodesAndSubscriptions();
      if (!silent) {
        _notice = AppNotice(
          NoticeKind.subscriptionUpdated,
          name: result.subscription.name,
          count: merged.length,
        );
      }
    } on Object catch (error) {
      final notice = _importFailure(error);
      // An ImportException says why. Anything else is a bug or a storage
      // error — not this source's state to record.
      if (notice.failure != null) {
        _subscriptions = [..._subscriptions]..[index] =
            subscription.failed(notice.failure!, status: notice.count);
        await _storage.writeSubscriptions(_subscriptions);
      }
      if (!silent) _notify(notice);
    } finally {
      _refreshing.remove(subscriptionId);
      notifyListeners();
    }
  }

  Future<void> removeSubscription(String subscriptionId) async {
    _nodes = [
      for (final node in _nodes)
        if (node.subscriptionId != subscriptionId) node,
    ];
    _subscriptions = [
      for (final item in _subscriptions)
        if (item.id != subscriptionId) item,
    ];
    // Auto names no node, so removing a source cannot invalidate it — but with
    // the last node gone there is nothing left to choose between, and the
    // sentinel would outlive the reason it was set. Compared against the raw
    // field rather than isAutoSelected, which is already false by then.
    if (_selectedNodeId == autoSelection) {
      if (_nodes.isEmpty) {
        _selectedNodeId = null;
        await _storage.writeSelectedNodeId(null);
      }
    } else if (_nodes.every((node) => node.id != _selectedNodeId)) {
      _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
      await _storage.writeSelectedNodeId(_selectedNodeId);
    }
    // Nothing left to fold, and ids are never reused.
    if (_collapsedSources.remove(subscriptionId)) {
      await _storage.writeCollapsedSources(_collapsedSources);
    }
    await _persistNodesAndSubscriptions();
    notifyListeners();
  }

  Future<void> removeNode(String nodeId) async {
    _nodes = [
      for (final node in _nodes)
        if (node.id != nodeId) node,
    ];
    // Same rule as removeSubscription: auto survives losing a node, but not
    // losing the last one.
    if (_selectedNodeId == nodeId ||
        (_selectedNodeId == autoSelection && _nodes.isEmpty)) {
      _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
      await _storage.writeSelectedNodeId(_selectedNodeId);
    }
    await _storage.writeNodes(_nodes);
    notifyListeners();
  }

  Future<void> toggleFavorite(String nodeId) async {
    _nodes = [
      for (final node in _nodes)
        if (node.id == nodeId)
          node.copyWith(favorite: !node.favorite)
        else
          node,
    ];
    await _storage.writeNodes(_nodes);
    notifyListeners();
  }

  /// Folds a source's rows away on the nodes page, or unfolds them.
  ///
  /// Persisted, because the alternative is asking the user to fold a long list
  /// away again every time they come back to the tab.
  Future<void> toggleSourceCollapsed(String sourceId) async {
    if (!_collapsedSources.remove(sourceId)) _collapsedSources.add(sourceId);
    await _storage.writeCollapsedSources(_collapsedSources);
    notifyListeners();
  }

  /// Switches how the nodes page orders rows, and remembers the choice.
  ///
  /// Does not go through [applySettings]: nothing here reaches the config, and a
  /// reload would cost a running tunnel its connections over a sort order.
  Future<void> setNodeSort(NodeSort sort) async {
    if (_nodeSort == sort) return;
    _nodeSort = sort;
    await _storage.writeNodeSort(sort);
    notifyListeners();
  }

  // ----------------------------------------------------------------- latency

  /// How long to wait for the engine's URL-test results before calling whatever
  /// has not reported unreachable. Generous: each member dials a real request
  /// through its proxy, and a slow-but-working node is worth waiting for.
  static const _defaultUrlTestTimeout = Duration(seconds: 10);

  /// Overridable so tests can exercise the timeout without waiting one out.
  final Duration _urlTestTimeout;

  /// Measures every node's latency and persists the results.
  ///
  /// Two very different measurements share this entry point. While the tunnel is
  /// up the engine is asked to URL-test the selector group, which times a real
  /// request *through* each proxy — the figure the user actually cares about.
  /// Otherwise there is no tunnel to measure through, so it falls back to a TCP
  /// handshake against each node's server address, which at least says whether
  /// the endpoint answers.
  Future<void> testLatency() async {
    if (_testingLatency || _nodes.isEmpty) return;
    _testingLatency = true;
    _nodes = [for (final node in _nodes) node.copyWith(clearLatency: true)];
    notifyListeners();

    try {
      if (!isConnected || !await _measureThroughEngine()) {
        await _probeNodes();
      }
      await _storage.writeNodes(_nodes);
    } on Object catch (error) {
      _fail(_short(error));
    } finally {
      _testingLatency = false;
      notifyListeners();
    }
  }

  /// TCP-handshake probe of every node, for when there is no tunnel.
  Future<void> _probeNodes() async {
    // Results stream in as each probe settles so a large subscription shows
    // progress instead of freezing until the slowest node times out.
    await for (final result in _latencyTester.probeAll(_nodes)) {
      _nodes = [
        for (final node in _nodes)
          node.id == result.nodeId
              ? node.copyWith(latencyMs: result.latencyMs)
              : node,
      ];
      notifyListeners();
    }
  }

  /// Asks the engine to URL-test the selector group and applies what comes back.
  ///
  /// Returns false when the request could not be handed over at all — the
  /// tunnel went away between the check and the call — so the caller can fall
  /// back to probing. A test that runs but reports nothing is not a failure:
  /// members that never report are marked unreachable, which is what a failed
  /// URL test means.
  Future<bool> _measureThroughEngine() async {
    // The engine speaks in outbound tags; only this mapping leads back to nodes.
    final nodeIds = {
      for (final node in _nodes) ConfigBuilder.outboundTag(node): node.id,
    };
    // Everything not yet accounted for. Emptying it ends the wait early.
    final pending = nodeIds.values.toSet();
    final settled = Completer<void>();

    final sub = _controller.groups.listen((group) {
      var changed = false;
      for (final entry in group.delays.entries) {
        final id = nodeIds[entry.key];
        // Group members that are not nodes — the `auto` group is itself one.
        if (id == null || !pending.contains(id)) continue;
        // 0 is "no result": not tested yet, or the test failed. Either way there
        // is nothing to show, so leave the row pending and let the timeout
        // decide.
        if (entry.value <= 0) continue;
        pending.remove(id);
        _nodes = [
          for (final node in _nodes)
            node.id == id ? node.copyWith(latencyMs: entry.value) : node,
        ];
        changed = true;
      }
      if (changed) notifyListeners();
      if (pending.isEmpty && !settled.isCompleted) settled.complete();
    });

    try {
      await _controller.urlTest();
    } on Object {
      await sub.cancel();
      return false;
    }

    try {
      // Results arrive on the group subscription, not from the call above.
      await settled.future.timeout(_urlTestTimeout, onTimeout: () {});
    } finally {
      await sub.cancel();
    }

    if (pending.isNotEmpty) {
      _nodes = [
        for (final node in _nodes)
          pending.contains(node.id)
              ? node.copyWith(latencyMs: ProxyNode.unreachableLatency)
              : node,
      ];
      notifyListeners();
    }
    return true;
  }

  // ------------------------------------------------------------------ config

  /// The config that would be sent to the runtime, for the diagnostics screen.
  ///
  /// Rendered with the Clash API secret masked. The sheet this feeds is one tap
  /// from the clipboard and from there into a bug report, and the token has no
  /// diagnostic value beyond being present.
  String previewConfig() =>
      ConfigBuilder.encode(_buildConfig(clashSecret: _maskedSecret));

  static const _maskedSecret = '<hidden>';

  Map<String, dynamic> _buildConfig({String? clashSecret}) =>
      ConfigBuilder.build(
        nodes: _nodes,
        selectedNodeId: selectedNode?.id,
        settings: _settings,
        clashSecret: clashSecret ?? _clashSecret,
        ruleSetDir: _ruleSetDir,
      );

  String _renderConfig() => ConfigBuilder.encode(_buildConfig());

  // --------------------------------------------------------------- rule sets

  /// Downloads fresh rule-sets over the current path.
  ///
  /// [silent] is for the automatic attempt after a connect: it reports nothing,
  /// because the user did not ask and a stale list is not a failure they need to
  /// act on. A manual update reports both outcomes.
  ///
  /// The engine reads these files when it starts, so a successful download
  /// applies at the next connect — said plainly in the notice rather than hidden
  /// behind a reload that would drop every live connection.
  Future<void> updateRuleSets({bool silent = false}) async {
    final dir = _ruleSetDir;
    if (dir == null) {
      if (!silent) {
        _notify(const AppNotice.error(NoticeKind.ruleSetsUnavailable));
      }
      return;
    }
    if (_updatingRuleSets) return;

    _updatingRuleSets = true;
    notifyListeners();
    try {
      // Connected means the loopback inbound is listening, and the download can
      // take the tunnel's exit instead of the direct path the app is pinned to.
      _ruleSetInstall = await _ruleSetUpdater.update(
        Directory(dir),
        viaLocalProxy: isConnected,
      );
      if (!silent) _notice = const AppNotice(NoticeKind.ruleSetsUpdated);
    } on Object {
      // The updater names the tags that failed, but in English and with nothing
      // the user can act on: offline, blocked, or an upstream hiccup all read the
      // same, and the old lists are still in place. So the notice stays a kind.
      if (!silent) _notice = const AppNotice.error(NoticeKind.ruleSetsUpdateFailed);
    } finally {
      _updatingRuleSets = false;
      notifyListeners();
    }
  }

  /// True when the lists on disk should be refreshed at the next opportunity.
  ///
  /// A bundled install always counts: its timestamp is when the app first ran,
  /// which says nothing about how old the shipped list itself is.
  bool get _ruleSetsAreStale {
    final install = _ruleSetInstall;
    if (install == null) return true;
    if (!install.downloaded) return true;
    return DateTime.now().difference(install.at) > _ruleSetMaxAge;
  }

  Future<void> _readRuleSetInstall() async {
    final dir = _ruleSetDir;
    if (dir == null) return;
    try {
      _ruleSetInstall = await BundledRuleSets.installed(Directory(dir));
      notifyListeners();
    } on Object {
      // Bookkeeping we cannot read only costs the row its subtitle.
    }
  }

  // ----------------------------------------------------------------- helpers

  void _onProxyState(ProxyState state) {
    final wasConnected = _proxyState.isConnected;
    _proxyState = state;
    if (state.stage == ProxyStage.error && state.message != null) {
      _notice = AppNotice.passthrough(state.message!);
    }
    // Traffic counters are meaningless once the tunnel is down.
    if (wasConnected && !state.isConnected) {
      _traffic = ProxyTraffic.zero;
      _downlinkHistory.clear();
      _uplinkHistory.clear();
      _connectionHistory.clear();
      _memoryHistory.clear();
    }
    // The one moment a rule-set download can reach an upstream this user cannot
    // reach directly. Deliberately after the tunnel is up and never before it:
    // the engine has already read the lists it is running on, so nothing here
    // can delay or fail a start.
    if (!wasConnected && state.isConnected) {
      _maybeAutoUpdateRuleSets();
      _maybeAutoRefreshSubscriptions();
    }
    notifyListeners();
  }

  void _maybeAutoUpdateRuleSets() {
    if (_autoUpdateTried || !_ruleSetsAreStale) return;
    _autoUpdateTried = true;
    // Unawaited on purpose: this must not hold up anything the connect does.
    updateRuleSets(silent: true);
  }

  /// Refreshes stale remote subscriptions, once per app run.
  ///
  /// Same reasoning as the rule-sets: a panel behind the censorship this app
  /// exists to get around is only reachable once the tunnel is up. Silent,
  /// because the user asked to connect, not to update — a failure lands on the
  /// source's own row, where they would look for it.
  void _maybeAutoRefreshSubscriptions() {
    if (_autoRefreshTried) return;
    _autoRefreshTried = true;
    for (final subscription in _subscriptions) {
      if (!subscription.isRemote) continue;
      final updatedAt = subscription.updatedAt;
      // A source that has never fetched is stale by definition.
      if (updatedAt != null &&
          DateTime.now().difference(updatedAt) < _subscriptionMaxAge) {
        continue;
      }
      // Unawaited, and one per source: refreshSubscription only touches its own
      // nodes, so overlapping fetches cannot interleave into each other.
      refreshSubscription(subscription.id, silent: true);
    }
  }

  /// Appends one traffic sample to each chart series, dropping the oldest once
  /// the window is full.
  void _pushHistory(ProxyTraffic value) {
    void push(List<int> series, int sample) {
      series.add(sample);
      if (series.length > _historyLength) {
        series.removeRange(0, series.length - _historyLength);
      }
    }

    push(_downlinkHistory, value.downlink);
    push(_uplinkHistory, value.uplink);
    push(_connectionHistory, value.connectionsOut);
    push(_memoryHistory, value.memory);
  }

  /// Merges an import result into state, replacing any nodes that share an id.
  void _absorb(Subscription subscription, ImportResult result) {
    final name = result.subscriptionName?.trim();
    final resolved = subscription.copyWith(
      name: name?.isNotEmpty == true ? name : null,
      nodeCount: result.nodes.length,
      updatedAt: DateTime.now(),
      expiresAt: result.expiresAt,
      usedBytes: result.usedBytes,
      totalBytes: result.totalBytes,
    );

    final incomingIds = {for (final node in result.nodes) node.id};
    _nodes = [
      for (final node in _nodes)
        if (!incomingIds.contains(node.id)) node,
      ...result.nodes,
    ];
    _subscriptions = [..._subscriptions, resolved];
    _selectedNodeId ??= _nodes.isEmpty ? null : _nodes.first.id;

    _persistNodesAndSubscriptions();
    _storage.writeSelectedNodeId(_selectedNodeId);

    _notice = AppNotice(
      NoticeKind.nodesImported,
      count: result.nodes.length,
      skipped: result.skipped > 0 ? result.skipped : null,
    );
  }

  Future<void> _persistNodesAndSubscriptions() async {
    await _storage.writeNodes(_nodes);
    await _storage.writeSubscriptions(_subscriptions);
  }

  /// Reports already-final text (a redacted exception or engine message).
  void _fail(String message) {
    _notice = AppNotice.passthrough(message);
    notifyListeners();
  }

  void _notify(AppNotice notice) {
    _notice = notice;
    notifyListeners();
  }

  /// Turns an import or refresh error into the notice for it.
  ///
  /// An [ImportException] carries a [SubscriptionFailure], which the UI
  /// localizes; the exception's own message is English and stays in the log.
  /// Anything else is unexpected, and keeps the passthrough path.
  static AppNotice _importFailure(Object error) => switch (error) {
        ImportException(:final failure, :final statusCode) => AppNotice(
            NoticeKind.importFailed,
            isError: true,
            failure: failure,
            count: statusCode,
          ),
        _ => AppNotice.passthrough(_short(error)),
      };

  /// Import/runtime errors are already redacted; keep them short for snackbars.
  static String _short(Object error) {
    final message =
        error.toString().replaceFirst(RegExp(r'^\w+Exception: '), '');
    return message.length > 160 ? '${message.substring(0, 157)}…' : message;
  }

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// A fresh Clash API token: 128 bits from the platform CSPRNG, hex.
  ///
  /// [Random.secure], not [Random]: the whole point of the token is that a
  /// co-resident app cannot arrive at it, and the default generator is seeded
  /// from a clock every app on the device can read.
  static String _newClashSecret() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _trafficSub?.cancel();
    _logSub?.cancel();
    _controller.dispose();
    _importer.dispose();
    _ruleSetUpdater.dispose();
    super.dispose();
  }
}
