part of 'app_state.dart';

// See AppStateConnection for why ChangeNotifier lint is intentionally scoped.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// Import/runtime errors are already redacted; keep them short for snackbars.
String _short(Object error) {
  final message = error.toString().replaceFirst(RegExp(r'^\w+Exception: '), '');
  return message.length > 160 ? '${message.substring(0, 157)}…' : message;
}

/// A fresh rule with an id, shared by nodes, subscriptions, and custom rules.
String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

/// A fresh Clash API token: 128 bits from the platform CSPRNG, hex.
///
/// [Random.secure], not [Random]: the whole point of the token is that a
/// co-resident app cannot arrive at it, and the default generator is seeded
/// from a clock every app on the device can read.
String _newClashSecret() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Turns an import or refresh error into the notice for it.
///
/// An [ImportException] carries a [SubscriptionFailure], which the UI
/// localizes; the exception's own message is English and stays in the log.
/// Anything else is unexpected, and keeps the passthrough path.
AppNotice _importFailure(Object error) => switch (error) {
      ImportException(:final failure, :final statusCode) => AppNotice(
          NoticeKind.importFailed,
          isError: true,
          failure: failure,
          count: statusCode,
        ),
      _ => AppNotice.passthrough(_short(error)),
    };

extension _AppStateRuntime on AppState {
  // ----------------------------------------------------------------- helpers

  bool get _acceptingWork => !_disposed && !_closing;

  /// Serializes every state mutation that crosses an async boundary.
  ///
  /// The queue is intentionally broader than the connection button: imports,
  /// refreshes, selections and persistence all update the same in-memory lists.
  /// Running them through one tail prevents a late write from putting an older
  /// snapshot back on disk after a newer operation has finished.
  Future<void> _enqueue(
    Future<void> Function() operation, {
    bool busy = false,
    bool allowWhenClosing = false,
  }) {
    if (_disposed || (_closing && !allowWhenClosing)) {
      return Future<void>.value();
    }

    if (busy) {
      _busyOperations++;
      if (!_busy) {
        _busy = true;
        notifyListeners();
      }
    }

    final previous = _operationTail;
    final result = previous.then((_) async {
      // Operations accepted before shutdown still sit in the tail, but a quit
      // request invalidates any one that has not started yet.
      if (_disposed && !allowWhenClosing) return;
      await operation();
    });
    _operationTail = result.then<void>(
      (_) => _finishBusy(busy),
      onError: (Object _, StackTrace __) => _finishBusy(busy),
    );
    return result;
  }

  void _finishBusy(bool busy) {
    if (!busy) return;
    _busyOperations--;
    if (_busyOperations == 0) {
      _busy = false;
      _notifyUnlessDisposed();
    }
  }

  bool _isCurrentRuntimeOperation(int operationId) =>
      !_disposed && !_closing && operationId == _runtimeOperationId;

  /// Notifies once for however many log lines are already queued.
  ///
  /// A zero-duration [Timer], not `scheduleMicrotask`. Stream events are
  /// delivered as microtasks, so a microtask scheduled from inside a listener
  /// interleaves with the deliveries still queued behind it — 300 lines produced
  /// 301 notifications that way, which is exactly what this exists to avoid. A
  /// timer is a macrotask: it runs only once the microtask queue is empty, by
  /// which point every line in the burst has landed in the buffer.
  ///
  /// Still ahead of the next frame, so the log does not visibly lag the engine.
  void _scheduleLogNotify() {
    if (_logNotify != null) return;
    _logNotify = Timer(Duration.zero, () {
      _logNotify = null;
      _notifyUnlessDisposed();
    });
  }

  /// [notifyListeners], dropped once [dispose] has run.
  ///
  /// For the tail of an async path only. A synchronous notify cannot outlive the
  /// object and should call the real thing, so a genuine use-after-dispose still
  /// shows up rather than being quietly swallowed everywhere.
  void _notifyUnlessDisposed() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Looks up the address the outside world sees us at.
  ///
  /// Routed through the tunnel whenever it is up, which is the whole point: a
  /// direct request reports the user's own line on Android and in desktop
  /// system-proxy mode, so it would claim the tunnel was doing nothing when it
  /// was working. See `ip_lookup.dart`.
  ///
  /// Overlapping calls are dropped rather than queued. Switching nodes a few
  /// times in a row should leave one request on the wire, not one per switch.
  Future<void> _refreshExitAddress() async {
    if (!_acceptingWork) return;
    if (_checkingExitAddress) return;
    final generation = _exitLookupGeneration;
    _checkingExitAddress = true;
    notifyListeners();
    try {
      final address = await _ipLookup.fetch(viaLocalProxy: isConnected);
      // A failed lookup clears the reading rather than leaving the last one on
      // screen: a stale address beside a tunnel that has since moved is worse
      // than admitting the check did not answer.
      if (!_disposed && generation == _exitLookupGeneration && isConnected) {
        _exitAddress = address;
      }
    } on Object {
      // The lookup is a secondary readout. A network failure must not become an
      // unhandled exception just because the caller intentionally did not await
      // the refresh from a node switch or a state callback.
      if (!_disposed && generation == _exitLookupGeneration) {
        _exitAddress = null;
      }
    } finally {
      _checkingExitAddress = false;
      _notifyUnlessDisposed();
    }
  }

  void _onProxyState(ProxyState state) {
    if (_disposed) return;
    final session = state.sessionId;
    if (session != null) {
      if (_latestProxySession != null && session < _latestProxySession!) {
        return;
      }
      _latestProxySession = session;
    }
    // A connected/starting event from a process that was superseded by a
    // disconnect is the most harmful late callback: it can make the UI show a
    // healthy tunnel while the controller has already been stopped.
    if (_desiredConnection == false && state.stage.isActive) return;

    final wasConnected = _proxyState.isConnected;
    _proxyState = state;
    if (state.stage == ProxyStage.error && _desiredConnection == true) {
      _desiredConnection = false;
    }
    if (state.stage == ProxyStage.error && state.message != null) {
      _notice = AppState.noticeFor(state.message!);
    }
    // Traffic counters are meaningless once the tunnel is down.
    if (wasConnected && !state.isConnected) {
      _exitLookupGeneration++;
      // Cleared rather than re-checked. The address on screen is the tunnel's
      // exit, and once the tunnel is gone the honest reading is none — going out
      // to ask would hand a third party the user's real address to answer a
      // question they did not ask.
      _exitAddress = null;
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
      _exitLookupGeneration++;
      _maybeAutoUpdateRuleSets();
      _maybeAutoRefreshSubscriptions();
      // Unawaited like the two above: this is a readout, and nothing about
      // connecting should wait on a third party answering.
      _refreshExitAddress();
    }
    notifyListeners();
  }

  Future<void> _maybeAutoUpdateRuleSets() async {
    if (_autoUpdateTried) return;
    _autoUpdateTried = true;
    // Waits for the disk record before judging staleness, not for the download.
    // Nothing about the connect is held up either way — the caller does not await
    // this — but the answer has to be based on what is actually installed.
    await _ruleSetInstallRead;
    if (!_ruleSetsAreStale) return;
    _updateRuleSetsIntent(silent: true);
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
          DateTime.now().difference(updatedAt) < AppState._subscriptionMaxAge) {
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
      if (series.length > AppState._historyLength) {
        series.removeRange(0, series.length - AppState._historyLength);
      }
    }

    push(_downlinkHistory, value.downlink);
    push(_uplinkHistory, value.uplink);
    push(_connectionHistory, value.connections);
    push(_memoryHistory, value.memory);
  }

  /// Merges an import result into state, replacing any nodes that share an id.
  Future<void> _absorb(Subscription subscription, ImportResult result) async {
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

    // Import completion means durable completion. The caller must be able to
    // close the app immediately after this future resolves without losing the
    // freshly imported nodes or selection.
    await _persistNodesAndSubscriptions();
    await _storage.writeSelectedNodeId(_selectedNodeId);

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

  /// Tears everything down in an order that can be waited on, then disposes.
  ///
  /// The quit path. [dispose] alone cannot put the desktop's proxy settings
  /// back — see [ProxyController.shutdown] — so quitting through it while
  /// connected in system-proxy mode leaves the whole machine offline.
  Future<void> _shutdownIntent() {
    final existing = _shutdownFuture;
    if (existing != null) return existing;
    if (_disposed) return Future<void>.value();

    // Stop accepting new work synchronously. Work already in the queue is still
    // allowed to drain before shutdown, so an import that just completed its
    // network step cannot be abandoned halfway through persistence.
    _closing = true;
    final future = _enqueue(_shutdown, allowWhenClosing: true);
    _shutdownFuture = future;
    return future;
  }

  Future<void> _shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _logNotify?.cancel();
    await _stateSub?.cancel();
    await _trafficSub?.cancel();
    await _logSub?.cancel();

    Object? failure;
    StackTrace? failureStack;
    try {
      // The one step that has to be awaited rather than fired.
      await _controller.shutdown();
    } on Object catch (error, stack) {
      // Continue releasing Dart-side resources even if a platform teardown
      // fails. The caller can still report the failure, while the controller's
      // own next-launch recovery remains available.
      failure = error;
      failureStack = stack;
    } finally {
      _importer.dispose();
      _ipLookup.dispose();
      _ruleSetUpdater.dispose();
      _finishDispose();
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }
}
