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
      await _controller.start(_renderConfig());
    } on Object catch (error) {
      if (_isCurrentRuntimeOperation(operationId)) _fail(_short(error));
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
    _selectedNodeId = id;
    await _storage.writeSelectedNodeId(id);
    notifyListeners();

    if (!isConnected) return;
    try {
      await _controller.selectOutbound(outboundTag);
      // The exit moved, so the address on screen is now the previous node's.
      // Unawaited: the switch is done either way, and a slow echo service must
      // not make selecting a node feel slow.
      _exitAddress = null;
      _exitLookupGeneration++;
      unawaited(refreshExitAddress());
    } on Object catch (error) {
      _notify(AppNotice.error(NoticeKind.switchFailed, detail: _short(error)));
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
    } on Object catch (error) {
      if (_runtimeOperationId == operationId) {
        _notify(
            AppNotice.error(NoticeKind.reloadFailed, detail: _short(error)));
      }
    }
  }
}
