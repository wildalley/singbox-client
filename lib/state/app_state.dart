/// Central app state: nodes, subscriptions, settings, and the proxy runtime.
///
/// Everything the UI reads goes through this [ChangeNotifier]. It owns
/// persistence and the [ProxyController] lifecycle so screens stay stateless.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/config_builder.dart';
import '../data/importer.dart';
import '../data/latency_tester.dart';
import '../data/storage.dart';
import '../models/app_settings.dart';
import '../models/node.dart';
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

  final int? count;
  final int? skipped;
}

class AppState extends ChangeNotifier {
  AppState({
    required Storage storage,
    required ProxyController controller,
    Importer? importer,
    LatencyTester? latencyTester,
  })  : _storage = storage,
        _controller = controller,
        _importer = importer ?? Importer(),
        _latencyTester = latencyTester ?? const LatencyTester() {
    _nodes = _storage.readNodes();
    _subscriptions = _storage.readSubscriptions();
    _settings = _storage.readSettings();
    _selectedNodeId = _storage.readSelectedNodeId();
    _proxyState = _controller.currentState;

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
  }

  static const _maxLogs = 500;

  /// 60 samples at roughly one per second — the rolling window the design plan
  /// asks for before any figure is compared against an earlier period.
  static const _historyLength = 60;

  final Storage _storage;
  final ProxyController _controller;
  final Importer _importer;
  final LatencyTester _latencyTester;

  late List<ProxyNode> _nodes;
  late List<Subscription> _subscriptions;
  late AppSettings _settings;
  String? _selectedNodeId;

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

  bool isRefreshing(String subscriptionId) =>
      _refreshing.contains(subscriptionId);

  String? get selectedNodeId => _selectedNodeId;

  ProxyNode? get selectedNode {
    if (_nodes.isEmpty) return null;
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
  Future<void> selectNode(ProxyNode node) async {
    _selectedNodeId = node.id;
    await _storage.writeSelectedNodeId(node.id);
    notifyListeners();

    if (!isConnected) return;
    try {
      await _controller.selectOutbound(ConfigBuilder.outboundTag(node));
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
      );
      _absorb(subscription, result);
    } on Object catch (error) {
      _fail(_short(error));
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
      _fail(_short(error));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Re-fetches a remote subscription, replacing only its own nodes.
  Future<void> refreshSubscription(String subscriptionId) async {
    final index =
        _subscriptions.indexWhere((item) => item.id == subscriptionId);
    if (index < 0) return;
    final subscription = _subscriptions[index];
    if (!subscription.isRemote) {
      _notify(AppNotice(
        NoticeKind.noUrlToRefresh,
        isError: true,
        name: subscription.name,
      ));
      return;
    }

    _refreshing.add(subscriptionId);
    notifyListeners();
    try {
      final result = await _importer.refresh(subscription);
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
      _notice = AppNotice(
        NoticeKind.subscriptionUpdated,
        name: result.subscription.name,
        count: merged.length,
      );
    } on Object catch (error) {
      _subscriptions = [..._subscriptions]..[index] =
          subscription.copyWith(lastError: _short(error));
      await _storage.writeSubscriptions(_subscriptions);
      _fail(_short(error));
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
    if (selectedNode == null || _nodes.every((n) => n.id != _selectedNodeId)) {
      _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
      await _storage.writeSelectedNodeId(_selectedNodeId);
    }
    await _persistNodesAndSubscriptions();
    notifyListeners();
  }

  Future<void> removeNode(String nodeId) async {
    _nodes = [
      for (final node in _nodes)
        if (node.id != nodeId) node,
    ];
    if (_selectedNodeId == nodeId) {
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

  // ----------------------------------------------------------------- latency

  /// Measures every node's latency concurrently and persists the results.
  Future<void> testLatency() async {
    if (_testingLatency || _nodes.isEmpty) return;
    _testingLatency = true;
    _nodes = [for (final node in _nodes) node.copyWith(clearLatency: true)];
    notifyListeners();

    try {
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
      await _storage.writeNodes(_nodes);
    } on Object catch (error) {
      _fail(_short(error));
    } finally {
      _testingLatency = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ config

  /// The config that would be sent to the runtime, for the diagnostics screen.
  String previewConfig() => ConfigBuilder.encode(_buildConfig());

  Map<String, dynamic> _buildConfig() => ConfigBuilder.build(
        nodes: _nodes,
        selectedNodeId: selectedNode?.id,
        settings: _settings,
      );

  String _renderConfig() => ConfigBuilder.encode(_buildConfig());

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
    notifyListeners();
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

  /// Import/runtime errors are already redacted; keep them short for snackbars.
  static String _short(Object error) {
    final message =
        error.toString().replaceFirst(RegExp(r'^\w+Exception: '), '');
    return message.length > 160 ? '${message.substring(0, 157)}…' : message;
  }

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  @override
  void dispose() {
    _stateSub?.cancel();
    _trafficSub?.cancel();
    _logSub?.cancel();
    _controller.dispose();
    _importer.dispose();
    super.dispose();
  }
}
