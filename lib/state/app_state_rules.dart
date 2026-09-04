part of 'app_state.dart';

// See AppStateConnection for why ChangeNotifier lint is intentionally scoped.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _AppStateRules on AppState {
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
  Future<void> _updateRuleSetsIntent({bool silent = false}) {
    if (!_acceptingWork) return Future<void>.value();
    final dir = _ruleSetDir;
    if (dir == null) {
      if (!silent) {
        _notify(const AppNotice.error(NoticeKind.ruleSetsUnavailable));
      }
      return Future<void>.value();
    }
    if (_updatingRuleSets) return Future<void>.value();

    _updatingRuleSets = true;
    notifyListeners();
    return _enqueue(() => _updateRuleSets(Directory(dir), silent: silent));
  }

  Future<void> _updateRuleSets(
    Directory directory, {
    required bool silent,
  }) async {
    try {
      // Connected means the loopback inbound is listening, and the download can
      // take the tunnel's exit instead of the direct path the app is pinned to.
      _ruleSetInstall = await _ruleSetUpdater.update(
        directory,
        viaLocalProxy: isConnected,
      );
      if (!silent) _notice = const AppNotice(NoticeKind.ruleSetsUpdated);
    } on Object {
      // The updater names the tags that failed, but in English and with nothing
      // the user can act on: offline, blocked, or an upstream hiccup all read the
      // same, and the old lists are still in place. So the notice stays a kind.
      if (!silent) {
        _notice = const AppNotice.error(NoticeKind.ruleSetsUpdateFailed);
      }
    } finally {
      _updatingRuleSets = false;
      _notifyUnlessDisposed();
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
    return DateTime.now().difference(install.at) > AppState._ruleSetMaxAge;
  }

  Future<void> _readRuleSetInstall() async {
    final dir = _ruleSetDir;
    if (dir == null) return;
    try {
      _ruleSetInstall = await BundledRuleSets.installed(Directory(dir));
      _notifyUnlessDisposed();
    } on Object {
      // Bookkeeping we cannot read only costs the row its subtitle.
    }
  }
}
