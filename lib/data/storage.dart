/// Local persistence for nodes, subscriptions, settings, and selection.
///
/// Uses `shared_preferences` with JSON payloads. Node credentials live in this
/// store, so nothing here may be written to logs.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/custom_rule.dart';
import '../models/node.dart';
import '../models/node_sort.dart';
import '../models/subscription.dart';

class Storage {
  Storage(this._prefs);

  final SharedPreferences _prefs;

  static const _kNodes = 'nodes.v1';
  static const _kSubscriptions = 'subscriptions.v1';
  static const _kSettings = 'settings.v1';
  static const _kSelectedNode = 'selected_node.v1';
  static const _kCollapsedSources = 'collapsed_sources.v1';
  static const _kClashSecret = 'clash_secret.v1';
  static const _kNodeSort = 'node_sort.v1';
  static const _kCustomRules = 'custom_rules.v1';

  static Future<Storage> open() async =>
      Storage(await SharedPreferences.getInstance());

  List<ProxyNode> readNodes() {
    final raw = _prefs.getString(_kNodes);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => ProxyNode.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on Object {
      // Corrupt payload: start clean rather than blocking app start.
      return const [];
    }
  }

  Future<void> writeNodes(List<ProxyNode> nodes) => _prefs.setString(
        _kNodes,
        jsonEncode(nodes.map((node) => node.toJson()).toList()),
      );

  /// The user's own routing rules, in the order they will be matched.
  ///
  /// Order is data here, not presentation: sing-box takes the first rule that
  /// matches, so the list order decides the behaviour and a read that reordered
  /// them would change what the tunnel does.
  List<CustomRule> readCustomRules() {
    final raw = _prefs.getString(_kCustomRules);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => CustomRule.fromJson(Map<String, dynamic>.from(item)))
          // A record with no id cannot be edited or removed through the UI,
          // which keys on it. Dropping it beats showing a row that ignores every
          // button on it.
          .where((rule) => rule.id.isNotEmpty)
          .toList();
    } on Object {
      // Corrupt payload: start clean rather than blocking app start.
      return const [];
    }
  }

  Future<void> writeCustomRules(List<CustomRule> rules) => _prefs.setString(
        _kCustomRules,
        jsonEncode(rules.map((rule) => rule.toJson()).toList()),
      );

  List<Subscription> readSubscriptions() {
    final raw = _prefs.getString(_kSubscriptions);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => Subscription.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<void> writeSubscriptions(List<Subscription> subscriptions) =>
      _prefs.setString(
        _kSubscriptions,
        jsonEncode(subscriptions.map((item) => item.toJson()).toList()),
      );

  AppSettings readSettings() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } on Object {
      return const AppSettings();
    }
  }

  Future<void> writeSettings(AppSettings settings) =>
      _prefs.setString(_kSettings, jsonEncode(settings.toJson()));

  String? readSelectedNodeId() => _prefs.getString(_kSelectedNode);

  Future<void> writeSelectedNodeId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kSelectedNode);
    } else {
      await _prefs.setString(_kSelectedNode, id);
    }
  }

  /// Source ids whose node list the user folded away on the nodes page.
  ///
  /// Persisted rather than held in the page's [State] so that folding a source
  /// away survives leaving the tab and restarting: it is work the user did, and
  /// a long list would have to be folded again on every visit.
  Set<String> readCollapsedSources() =>
      _prefs.getStringList(_kCollapsedSources)?.toSet() ?? const {};

  Future<void> writeCollapsedSources(Set<String> ids) =>
      _prefs.setStringList(_kCollapsedSources, ids.toList());

  /// How the nodes page orders rows within a source.
  ///
  /// Kept here rather than in [AppSettings] because it changes nothing about the
  /// tunnel: settings go through `applySettings`, which reloads a running
  /// config, and reordering a list is no reason to drop connections.
  NodeSort readNodeSort() => NodeSort.fromKey(_prefs.getString(_kNodeSort));

  Future<void> writeNodeSort(NodeSort sort) =>
      _prefs.setString(_kNodeSort, sort.key);

  /// The bearer token the running config's Clash API listener requires.
  ///
  /// Persisted rather than regenerated per run so that a token handed to
  /// anything outside the app keeps working, and so a reload mid-session cannot
  /// change it out from under a live listener. Generated once, then never shown
  /// or logged — this is a credential like any node's password.
  String? readClashSecret() => _prefs.getString(_kClashSecret);

  Future<void> writeClashSecret(String secret) =>
      _prefs.setString(_kClashSecret, secret);
}
