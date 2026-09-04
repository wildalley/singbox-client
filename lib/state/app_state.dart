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
import '../data/ip_lookup.dart';
import '../data/latency_tester.dart';
import '../data/rule_set_updater.dart';
import '../data/rule_sets.dart';
import '../data/storage.dart';
import '../models/app_settings.dart';
import '../models/custom_rule.dart';
import '../models/log_buffer.dart';
import '../models/node.dart';
import '../models/node_sort.dart';
import '../models/proxy_state.dart';
import '../models/subscription.dart';
import '../platform/proxy_controller.dart';

part 'app_state_notice.dart';
part 'app_state_connection.dart';
part 'app_state_import.dart';
part 'app_state_latency.dart';
part 'app_state_config.dart';
part 'app_state_rules.dart';
part 'app_state_runtime.dart';

class AppState extends ChangeNotifier {
  AppState({
    required Storage storage,
    required ProxyController controller,
    Importer? importer,
    LatencyTester? latencyTester,
    RuleSetUpdater? ruleSetUpdater,
    IpLookup? ipLookup,
    String? ruleSetDir,
    Duration? urlTestTimeout,
  })  : _urlTestTimeout = urlTestTimeout ?? _defaultUrlTestTimeout,
        _storage = storage,
        _controller = controller,
        _importer = importer ?? Importer(),
        _ipLookup = ipLookup ?? IpLookup(),
        _latencyTester = latencyTester ?? const LatencyTester(),
        _ruleSetUpdater = ruleSetUpdater ?? RuleSetUpdater(),
        _ruleSetDir = ruleSetDir {
    _nodes = _storage.readNodes();
    _subscriptions = _storage.readSubscriptions();
    _settings = _storage.readSettings();
    _selectedNodeId = _storage.readSelectedNodeId();
    _collapsedSources = {..._storage.readCollapsedSources()};
    _nodeSort = _storage.readNodeSort();
    _customRules = _storage.readCustomRules();
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
      // The buffer drops its own oldest entry at capacity, so there is no
      // trimming step here.
      _logs.add(entry);
      _scheduleLogNotify();
    });

    // Shown in Settings; failure just leaves the row as unknown.
    _controller.coreVersion().then((value) {
      _coreVersion = value;
      // Guarded: on the desktop this shells out to `sing-box version`, so a
      // window closed while it runs disposes the state before it answers.
      _notifyUnlessDisposed();
    }, onError: (_) {});

    _ruleSetInstallRead = _readRuleSetInstall();
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
  final IpLookup _ipLookup;
  final LatencyTester _latencyTester;
  final RuleSetUpdater _ruleSetUpdater;

  /// Where the bundled `.srs` rule-sets were unpacked, or null if they are not
  /// on disk — see [ConfigBuilder.build].
  final String? _ruleSetDir;

  /// How long to wait for the engine's URL-test results.
  static const _defaultUrlTestTimeout = Duration(seconds: 10);
  final Duration _urlTestTimeout;

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

  /// The address the outside world last reported back, or null when it has not
  /// been looked up or the lookup failed.
  ExitAddress? _exitAddress;

  /// A lookup is in flight. Also the concurrency guard: switching nodes twice in
  /// a second must not put two requests on the wire.
  var _checkingExitAddress = false;
  var _exitLookupGeneration = 0;

  /// Fixed-capacity, so a burst costs one slot each rather than shifting the
  /// whole list per line. See [RingBuffer].
  final _logs = RingBuffer<ProxyLogEntry>(_maxLogs);

  /// The pending coalesced log notification, if one is queued.
  ///
  /// The engine emits in bursts — one line per connection at debug level — and
  /// each line used to notify on its own, so 300 lines rebuilt the app 300 times
  /// within a frame nobody ever saw. Held rather than fire-and-forget so [dispose]
  /// can cancel it: a timer that outlives the state notifies a disposed
  /// ChangeNotifier, and the test framework rightly fails a pending one.
  Timer? _logNotify;

  /// Rolling per-sample history for the charts, oldest first. Lives here rather
  /// than in the home page's State so switching tabs doesn't blank the charts.
  final _downlinkHistory = <int>[];
  final _uplinkHistory = <int>[];
  final _connectionHistory = <int>[];
  final _memoryHistory = <int>[];

  StreamSubscription<ProxyState>? _stateSub;
  StreamSubscription<ProxyTraffic>? _trafficSub;
  StreamSubscription<ProxyLogEntry>? _logSub;

  /// Set by [dispose]. Anything that resumes after an await checks it: an
  /// unawaited task started from the connect hook — a rule-set update, an
  /// address lookup — can still be in flight when the state goes away, and
  /// notifying a disposed ChangeNotifier throws.
  var _disposed = false;
  var _closing = false;
  var _didDispose = false;

  /// All state-changing async work runs through this tail. Keeping the tail
  /// fulfilled even when an operation fails means a failed import or reload
  /// cannot permanently jam later user actions.
  Future<void> _operationTail = Future<void>.value();
  var _busyOperations = 0;
  Future<void>? _shutdownFuture;

  /// Invalidates a pending connect/reload as soon as the newer runtime intent is
  /// issued, rather than waiting for the older controller call to return.
  var _runtimeOperationId = 0;
  int? _latestProxySession;
  bool? _desiredConnection;

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

  /// The user's own routing rules, in match order.
  late List<CustomRule> _customRules;

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
  ExitAddress? get exitAddress => _exitAddress;
  bool get isCheckingExitAddress => _checkingExitAddress;

  /// The log, oldest first.
  ///
  /// Handed out directly rather than copied. [RingBuffer] refuses every mutating
  /// [List] setter, so this is already read-only — and copying it was the second
  /// O(n) per line, paid on every build while lines were arriving fastest.
  List<ProxyLogEntry> get logs => _logs;

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

  /// The user's own rules, in the order they are matched.
  List<CustomRule> get customRules => List.unmodifiable(_customRules);

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

  // ----------------------------------------------------------- public intents

  // Keep the public surface on AppState itself. The implementation is grouped
  // into domain extensions in the part files below, so callers do not need to
  // know which extension library provides a method.
  Future<void> connect() => _connectIntent();
  Future<void> disconnect() => _disconnectIntent();
  Future<void> toggleConnection() => _toggleConnectionIntent();
  Future<void> clearLogs() => _clearLogs();
  Future<void> selectNode(ProxyNode node) => _selectNodeIntent(node);
  Future<void> selectAuto() => _selectAutoIntent();
  Future<void> applySettings(AppSettings settings) =>
      _applySettingsIntent(settings);

  Future<void> importFromText(String text, {String? name}) =>
      _importFromTextIntent(text, name: name);
  Future<void> importFromFile(String path, {String? name}) =>
      _importFromFileIntent(path, name: name);
  Future<void> refreshSubscription(
    String subscriptionId, {
    bool silent = false,
  }) =>
      _refreshSubscriptionIntent(subscriptionId, silent: silent);
  Future<void> removeSubscription(String subscriptionId) =>
      _removeSubscriptionIntent(subscriptionId);
  Future<void> removeNode(String nodeId) => _removeNodeIntent(nodeId);
  Future<void> toggleFavorite(String nodeId) => _toggleFavoriteIntent(nodeId);
  Future<void> toggleSourceCollapsed(String sourceId) =>
      _toggleSourceCollapsedIntent(sourceId);
  Future<void> setNodeSort(NodeSort sort) => _setNodeSortIntent(sort);

  Future<void> testLatency() => _testLatencyIntent();
  String previewConfig() => _previewConfig();
  Future<void> addCustomRule(CustomRule rule) => _addCustomRuleIntent(rule);
  Future<void> updateCustomRule(CustomRule rule) =>
      _updateCustomRuleIntent(rule);
  Future<void> removeCustomRule(String id) => _removeCustomRuleIntent(id);
  Future<void> moveCustomRule(int from, int to) =>
      _moveCustomRuleIntent(from, to);
  CustomRule newCustomRule() => _newCustomRule();
  Future<void> updateRuleSets({bool silent = false}) =>
      _updateRuleSetsIntent(silent: silent);
  Future<void> refreshExitAddress() => _refreshExitAddress();
  Future<void> shutdown() => _shutdownIntent();

  Future<void>? _ruleSetInstallRead;

  /// Turns an error message into a notice.
  ///
  /// Engine output is passed through as-is; the markers the runtime encodes for
  /// the failures it detected itself become kinds the UI can translate. Public
  /// because the home page shows the same failure as a stage detail, and one
  /// decode shared beats two that can drift apart.
  static AppNotice noticeFor(String message) =>
      switch (EngineProblem.of(message)) {
        EngineProblem.missing =>
          const AppNotice.error(NoticeKind.engineMissing),
        EngineProblem.tooOld => AppNotice.error(
            NoticeKind.engineTooOld,
            detail: EngineProblem.detailOf(message),
          ),
        EngineProblem.unprivileged => AppNotice.error(
            NoticeKind.tunUnprivileged,
            detail: EngineProblem.detailOf(message),
          ),
        null => AppNotice.passthrough(message),
      };

  @override
  void dispose() {
    if (_didDispose) return;
    _closing = true;
    _disposed = true;
    _logNotify?.cancel();
    _stateSub?.cancel();
    _trafficSub?.cancel();
    _logSub?.cancel();
    _controller.dispose();
    _importer.dispose();
    _ipLookup.dispose();
    _ruleSetUpdater.dispose();
    _didDispose = true;
    super.dispose();
  }

  void _finishDispose() {
    if (_didDispose) return;
    _didDispose = true;
    super.dispose();
  }
}
