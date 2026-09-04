part of 'app_state.dart';

// See AppStateConnection for why ChangeNotifier lint is intentionally scoped.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _AppStateImport on AppState {
  // ------------------------------------------------------------------ import

  /// Imports pasted text: subscription URL, share links, or sing-box JSON.
  Future<void> _importFromTextIntent(String text, {String? name}) => _enqueue(
        () => _importFromText(text, name: name),
        busy: true,
      );

  Future<void> _importFromText(String text, {String? name}) async {
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
      await _absorb(subscription, result);
    } on Object catch (error) {
      _notify(_importFailure(error));
    }
  }

  /// Imports a sing-box config or link list from a file on disk.
  Future<void> _importFromFileIntent(String path, {String? name}) => _enqueue(
        () => _importFromFile(path, name: name),
        busy: true,
      );

  Future<void> _importFromFile(String path, {String? name}) async {
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
      await _absorb(subscription, result);
    } on Object catch (error) {
      _notify(_importFailure(error));
    }
  }

  /// Re-fetches a remote subscription, replacing only its own nodes.
  ///
  /// [silent] suppresses the notices, for the automatic refresh on connect: the
  /// user did not ask for it, so it has no business interrupting them. A failure
  /// is still recorded on the subscription, which is where they would look.
  Future<void> _refreshSubscriptionIntent(
    String subscriptionId, {
    bool silent = false,
  }) {
    if (!_acceptingWork) return Future<void>.value();
    // The automatic refresh on connect and a user's tap on the same row can
    // land together; the second would replace this source's nodes twice from
    // two fetches, and the later answer is not necessarily the newer one.
    if (_refreshing.contains(subscriptionId)) return Future<void>.value();
    final index =
        _subscriptions.indexWhere((item) => item.id == subscriptionId);
    if (index < 0) return Future<void>.value();
    final subscription = _subscriptions[index];
    if (!subscription.isRemote) {
      if (!silent) {
        _notify(AppNotice(
          NoticeKind.noUrlToRefresh,
          isError: true,
          name: subscription.name,
        ));
      }
      return Future<void>.value();
    }

    _refreshing.add(subscriptionId);
    notifyListeners();
    return _enqueue(
      () => _refreshSubscription(
        subscriptionId,
        silent: silent,
      ),
    );
  }

  Future<void> _refreshSubscription(
    String subscriptionId, {
    required bool silent,
  }) async {
    try {
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
      final index =
          _subscriptions.indexWhere((item) => item.id == subscriptionId);
      final subscription = index < 0 ? null : _subscriptions[index];
      // An ImportException says why. Anything else is a bug or a storage
      // error — not this source's state to record.
      if (notice.failure != null && subscription != null) {
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

  Future<void> _removeSubscriptionIntent(String subscriptionId) =>
      _enqueue(() => _removeSubscription(subscriptionId));

  Future<void> _removeSubscription(String subscriptionId) async {
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
    if (_selectedNodeId == AppState.autoSelection) {
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

  Future<void> _removeNodeIntent(String nodeId) =>
      _enqueue(() => _removeNode(nodeId));

  Future<void> _removeNode(String nodeId) async {
    _nodes = [
      for (final node in _nodes)
        if (node.id != nodeId) node,
    ];
    // Same rule as removeSubscription: auto survives losing a node, but not
    // losing the last one.
    if (_selectedNodeId == nodeId ||
        (_selectedNodeId == AppState.autoSelection && _nodes.isEmpty)) {
      _selectedNodeId = _nodes.isEmpty ? null : _nodes.first.id;
      await _storage.writeSelectedNodeId(_selectedNodeId);
    }
    await _storage.writeNodes(_nodes);
    notifyListeners();
  }

  Future<void> _toggleFavoriteIntent(String nodeId) =>
      _enqueue(() => _toggleFavorite(nodeId));

  Future<void> _toggleFavorite(String nodeId) async {
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
  Future<void> _toggleSourceCollapsedIntent(String sourceId) =>
      _enqueue(() => _toggleSourceCollapsed(sourceId));

  Future<void> _toggleSourceCollapsed(String sourceId) async {
    if (!_collapsedSources.remove(sourceId)) _collapsedSources.add(sourceId);
    await _storage.writeCollapsedSources(_collapsedSources);
    notifyListeners();
  }

  /// Switches how the nodes page orders rows, and remembers the choice.
  ///
  /// Does not go through [applySettings]: nothing here reaches the config, and a
  /// reload would cost a running tunnel its connections over a sort order.
  Future<void> _setNodeSortIntent(NodeSort sort) =>
      _enqueue(() => _setNodeSort(sort));

  Future<void> _setNodeSort(NodeSort sort) async {
    if (_nodeSort == sort) return;
    _nodeSort = sort;
    await _storage.writeNodeSort(sort);
    notifyListeners();
  }
}
