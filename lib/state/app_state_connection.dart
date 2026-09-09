part of 'app_state.dart';

// Extension members call the protected ChangeNotifier API through the same
// library as AppState; keep the analyzer focused on the public facade.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _AppStateConnection on AppState {
  // ------------------------------------------------------------- connection

  /// Queues a connect intent. The id is allocated before the first await so a
  /// disconnect requested while permission/start is pending can invalidate the
  /// older intent before it reaches the controller.
  Future<void> _connectIntent() {
    if (!_acceptingWork) return Future<void>.value();
    final operationId = ++_runtimeOperationId;
    _desiredConnection = true;
    return _enqueue(
      () => _connect(operationId),
      busy: true,
    );
  }

  Future<void> _connect(int operationId) async {
    if (!_isCurrentRuntimeOperation(operationId)) return;
    if (_nodes.isEmpty) {
      _desiredConnection = false;
      _notify(const AppNotice.error(NoticeKind.needNodes));
      return;
    }
    // A second connect tap is harmless once the first one has completed. This
    // also protects platform adapters whose start method is not idempotent.
    if (isConnected || _proxyState.stage == ProxyStage.starting) return;

    try {
      final granted = await _controller.requestPermission();
      if (!_isCurrentRuntimeOperation(operationId)) return;
      if (!granted) {
        _desiredConnection = false;
        _notify(const AppNotice.error(NoticeKind.permissionDenied));
        return;
      }
      // Ports are chosen here, not at build time: this is the last moment
      // before the core binds them, so a number another program grabbed while
      // the app sat idle is still caught. They then hold for the session, since
      // a reload has to render what the live core is already listening on.
      await _allocatePorts();
      if (!_isCurrentRuntimeOperation(operationId)) return;

      await _controller.start(_renderConfig());
    } on FormatException catch (error) {
      // The config never left the app, so nothing is running and there is
      // nothing to stop — but the button has to come back off "connecting", and
      // a stale intent would otherwise reconnect on the next state event.
      if (!_isCurrentRuntimeOperation(operationId)) return;
      _desiredConnection = false;
      _notify(AppNotice.error(NoticeKind.configInvalid, detail: error.message));
    } on Object catch (error) {
      if (_isCurrentRuntimeOperation(operationId)) _fail(_short(error));
    }
  }

  /// Picks the session's loopback ports, preferring the documented pair.
  ///
  /// A failure here is not fatal: the allocator only probes, so the fallback is
  /// the preferred pair — exactly what every build did before this existed.
  Future<void> _allocatePorts() async {
    try {
      final ports = await _portAllocator(
        preferredClashApiPort: ConfigBuilder.defaultClashApiPort,
        preferredLocalProxyPort: ConfigBuilder.defaultLocalProxyPort,
      );
      _clashApiPort = ports.clashApiPort;
      _localProxyPort = ports.localProxyPort;
    } on Object {
      _clashApiPort = ConfigBuilder.defaultClashApiPort;
      _localProxyPort = ConfigBuilder.defaultLocalProxyPort;
    }
  }

  /// Queues a disconnect intent and invalidates any older start/reload intent.
  Future<void> _disconnectIntent() {
    if (!_acceptingWork) return Future<void>.value();
    final operationId = ++_runtimeOperationId;
    _desiredConnection = false;
    return _enqueue(
      () => _disconnect(operationId),
      busy: true,
    );
  }

  Future<void> _disconnect(int operationId) async {
    if (!_isCurrentRuntimeOperation(operationId)) return;
    try {
      await _controller.stop();
    } on Object catch (error) {
      if (_isCurrentRuntimeOperation(operationId)) _fail(_short(error));
    }
  }

  /// Evaluates the connection state when it reaches the queue, not when the
  /// button callback is created. Two quick taps therefore become connect then
  /// disconnect instead of two starts based on the same stale state.
  Future<void> _toggleConnectionIntent() {
    if (!_acceptingWork) return Future<void>.value();
    return _enqueue(() async {
      final operationId = ++_runtimeOperationId;
      final currentlyDesired = _desiredConnection ?? isConnected;
      if (currentlyDesired) {
        _desiredConnection = false;
        await _disconnect(operationId);
      } else {
        _desiredConnection = true;
        await _connect(operationId);
      }
    }, busy: true);
  }

  /// Removes both the visible log list and the engine's retained buffer.
  ///
  /// The local list is cleared synchronously so the page responds immediately;
  /// clearing the native copy is best-effort because the service may already
  /// have stopped after a failed connection.
  Future<void> _clearLogs() async {
    if (!_acceptingWork) return;
    _logs.clear();
    _logNotify?.cancel();
    _logNotify = null;
    notifyListeners();

    await _enqueue(() async {
      try {
        await _controller.clearLogs();
      } on Object catch (_) {
        // The visible viewer must remain usable when the native service is gone.
      }
    });
  }

  /// Selects [node]. While connected this switches the live selector outbound
  /// instead of restarting the tunnel.
  Future<void> _selectNodeIntent(ProxyNode node) =>
      _enqueue(() => _select(node.id, ConfigBuilder.outboundTag(node)));

  /// Hands the choice of exit to the engine's `urltest` group.
  ///
  /// The group is already in every config with nodes, measuring its members on
  /// its own interval, so this only has to point the selector at it.
  Future<void> _selectAutoIntent() =>
      _enqueue(() => _select(AppState.autoSelection, ConfigTags.auto));

  /// Records a selection and, while connected, moves the live selector to it.
  Future<void> _select(String id, String outboundTag) async {
    final previousId = _selectedNodeId;
    final connected = isConnected;
    try {
      if (connected) {
        // A connected selection is committed only after the runtime accepts it.
        // This keeps the highlighted node and the persisted default honest when
        // the platform control channel is unavailable.
        await _controller.selectOutbound(outboundTag);
      }
      _selectedNodeId = id;
      await _storage.writeSelectedNodeId(id);
      notifyListeners();

      if (!connected) return;
      // The exit moved, so the address on screen is now the previous node's.
      // Clear it before starting the fresh lookup so an old address can never be
      // mistaken for the new exit while the proxy connection is being replaced.
      _exitAddress = null;
      _exitLookupGeneration++;
      notifyListeners();
      unawaited(refreshExitAddress());
    } on Object catch (error) {
      // The live runtime may have rejected the switch. Keep the old selection in
      // memory and on disk instead of presenting a choice that did not take.
      if (connected && _selectedNodeId != previousId) {
        _selectedNodeId = previousId;
        await _storage.writeSelectedNodeId(previousId);
        notifyListeners();
      }
      _notify(AppNotice.error(NoticeKind.switchFailed, detail: _short(error)));
    }
  }

  /// Persists one node's upstream and reloads the live config when needed.
  ///
  /// The UI filters invalid edges, but this repeats the guard at the state
  /// boundary so a stale sheet cannot write a cycle.
  Future<void> _setNodeDetourIntent(
    String nodeId,
    String? detourNodeId,
  ) =>
      _enqueue(() => _setNodeDetour(nodeId, detourNodeId));

  Future<void> _setNodeDetour(String nodeId, String? detourNodeId) async {
    if (!_nodes.any((node) => node.id == nodeId)) return;
    if (detourNodeId != null &&
        (!_nodes.any((node) => node.id == detourNodeId) ||
            wouldCreateDetourCycle(_nodes, nodeId, detourNodeId))) {
      return;
    }

    _nodes = [
      for (final node in _nodes)
        if (node.id == nodeId)
          node.copyWith(
            detourNodeId: detourNodeId,
            clearDetour: detourNodeId == null,
          )
        else
          node,
    ];
    await _storage.writeNodes(_nodes);
    notifyListeners();

    if (!isConnected) return;
    final operationId = _runtimeOperationId;
    try {
      await _controller.reload(_renderConfig());
    } on FormatException catch (error) {
      if (_runtimeOperationId == operationId) {
        _notify(
          AppNotice.error(NoticeKind.configInvalid, detail: error.message),
        );
      }
    } on Object catch (error) {
      if (_runtimeOperationId == operationId) {
        _notify(
            AppNotice.error(NoticeKind.reloadFailed, detail: _short(error)));
      }
    }
  }

  /// Persists settings and only reloads when the rendered runtime config changes.
  Future<void> _applySettingsIntent(AppSettings settings) =>
      _enqueue(() => _applySettings(settings));

  Future<void> _applySettings(AppSettings settings) async {
    final runtimeChanged = !_settings.hasSameRuntimeConfig(settings);
    _settings = settings;
    await _storage.writeSettings(settings);
    notifyListeners();

    if (!runtimeChanged || !isConnected) return;
    final operationId = _runtimeOperationId;
    try {
      await _controller.reload(_renderConfig());
    } on FormatException catch (error) {
      // Named for what it is rather than folded into reloadFailed: the live
      // tunnel is still up on the previous config, which is the opposite of
      // what "reload failed" leads a user to check.
      if (_runtimeOperationId == operationId) {
        _notify(
          AppNotice.error(NoticeKind.configInvalid, detail: error.message),
        );
      }
    } on Object catch (error) {
      if (_runtimeOperationId == operationId) {
        _notify(
            AppNotice.error(NoticeKind.reloadFailed, detail: _short(error)));
      }
    }
  }
}
