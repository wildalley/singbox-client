/// Local persistence for nodes, subscriptions, settings, and selection.
///
/// Uses `shared_preferences` with JSON payloads. Node credentials live in this
/// store, so nothing here may be written to logs.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/node.dart';
import '../models/subscription.dart';

class Storage {
  Storage(this._prefs);

  final SharedPreferences _prefs;

  static const _kNodes = 'nodes.v1';
  static const _kSubscriptions = 'subscriptions.v1';
  static const _kSettings = 'settings.v1';
  static const _kSelectedNode = 'selected_node.v1';

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
}
