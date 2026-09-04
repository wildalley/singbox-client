part of 'app_state.dart';

// See AppStateConnection for why ChangeNotifier lint is intentionally scoped.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _AppStateLatency on AppState {
  // ----------------------------------------------------------------- latency

  /// Measures every node's latency and persists the results.
  ///
  /// Two very different measurements share this entry point. While the tunnel is
  /// up the engine is asked to URL-test the selector group, which times a real
  /// request *through* each proxy — the figure the user actually cares about.
  /// Otherwise there is no tunnel to measure through, so it falls back to a TCP
  /// handshake against TCP-based node endpoints, which at least says whether the
  /// endpoint answers. UDP/QUIC nodes stay untested on this path: a TCP failure
  /// against a Hysteria2 port would be a false failure. Connect the tunnel before
  /// testing those nodes so the engine can URL-test them.
  Future<void> _testLatencyIntent() {
    if (!_acceptingWork) return Future<void>.value();
    if (_testingLatency || _nodes.isEmpty) return Future<void>.value();
    _testingLatency = true;
    _nodes = [for (final node in _nodes) node.copyWith(clearLatency: true)];
    notifyListeners();

    return _enqueue(_testLatency);
  }

  Future<void> _testLatency() async {
    try {
      if (!isConnected || !await _measureThroughEngine()) {
        await _probeNodes();
      }
      await _storage.writeNodes(_nodes);
    } on Object catch (error) {
      _fail(_short(error));
    } finally {
      _testingLatency = false;
      _notifyUnlessDisposed();
    }
  }

  /// TCP-handshake probe of TCP-based nodes, for when there is no tunnel.
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
}
