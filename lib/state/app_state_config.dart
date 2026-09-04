part of 'app_state.dart';

// See AppStateConnection for why ChangeNotifier lint is intentionally scoped.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _AppStateConfig on AppState {
  // ------------------------------------------------------------------ config

  /// The config that would be sent to the runtime, for the diagnostics screen.
  ///
  /// Rendered with the Clash API secret masked. The sheet this feeds is one tap
  /// from the clipboard and from there into a bug report, and the token has no
  /// diagnostic value beyond being present.
  String _previewConfig() =>
      ConfigBuilder.encode(_buildConfig(clashSecret: _maskedSecret));

  Map<String, dynamic> _buildConfig({String? clashSecret}) =>
      ConfigBuilder.build(
        nodes: _nodes,
        selectedNodeId: selectedNode?.id,
        settings: _settings,
        clashSecret: clashSecret ?? _clashSecret,
        customRules: _customRules,
        ruleSetDir: _ruleSetDir,
      );

  String _renderConfig() => ConfigBuilder.encode(_buildConfig());

  // ------------------------------------------------------------ custom rules

  /// Appends a rule and applies it.
  ///
  /// Appended rather than prepended: rules are matched in order, and a user
  /// adding a rule expects it after the ones already there, not silently ahead
  /// of them.
  Future<void> _addCustomRuleIntent(CustomRule rule) =>
      _enqueue(() => _writeCustomRules([..._customRules, rule]));

  /// Replaces the rule with the same id, or does nothing if it is gone.
  Future<void> _updateCustomRuleIntent(CustomRule rule) async {
    final index = _customRules.indexWhere((item) => item.id == rule.id);
    if (index < 0) return;
    final next = [..._customRules]..[index] = rule;
    await _enqueue(() => _writeCustomRules(next));
  }

  Future<void> _removeCustomRuleIntent(String id) => _enqueue(
        () => _writeCustomRules(
          _customRules.where((rule) => rule.id != id).toList(),
        ),
      );

  /// Moves the rule at [from] to [to], because order is behaviour.
  Future<void> _moveCustomRuleIntent(int from, int to) async {
    if (from < 0 || from >= _customRules.length) return;
    if (to < 0 || to >= _customRules.length || from == to) return;
    final next = [..._customRules];
    next.insert(to, next.removeAt(from));
    await _enqueue(() => _writeCustomRules(next));
  }

  /// A fresh rule with an id, ready to be edited. Not persisted until added.
  ///
  /// Same id scheme as nodes and subscriptions: a base-36 microsecond stamp,
  /// which cannot collide within one process.
  CustomRule _newCustomRule() => CustomRule(
        id: _newId(),
        matcher: RuleMatcher.domainSuffix,
        value: '',
        target: RuleTarget.proxy,
      );

  /// Persists [rules] and pushes them to a running tunnel.
  ///
  /// The reload is the point. Unlike the bundled rule-sets — which the engine
  /// reads off disk at start, so a download only applies at the next connect —
  /// route rules are part of the config, and reloading is the only way a rule the
  /// user just typed takes effect now. It costs the live connections, which is
  /// the honest price of changing where traffic goes.
  Future<void> _writeCustomRules(List<CustomRule> rules) async {
    _customRules = rules;
    await _storage.writeCustomRules(rules);
    notifyListeners();

    if (!isConnected) return;
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

const _maskedSecret = '<hidden>';
