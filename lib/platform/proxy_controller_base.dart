/// Platform-neutral proxy runtime boundary.
library;

import 'dart:async';

import '../models/proxy_state.dart';

/// The UI-facing contract shared by Android and desktop runtimes.
abstract interface class ProxyController {
  Stream<ProxyState> get states;
  Stream<ProxyTraffic> get traffic;
  Stream<ProxyLogEntry> get logs;

  /// Outbound group updates, including each member's URL-test delay.
  Stream<ProxyGroup> get groups;

  ProxyState get currentState;

  /// Requests the platform VPN permission. Returns true when granted.
  Future<bool> requestPermission();

  /// Starts the tunnel with [configJson] (a rendered sing-box config).
  Future<void> start(String configJson);

  Future<void> stop();

  /// Clears the engine's in-memory log buffer.
  Future<void> clearLogs();

  /// Applies a new config without tearing the tunnel down when supported.
  Future<void> reload(String configJson);

  /// Selects [outboundTag] inside the `selector` group at runtime.
  Future<void> selectOutbound(String outboundTag);

  /// Asks the engine to URL-test every member of the main selector group.
  Future<void> urlTest();

  /// Version of the bundled proxy core, or null when it cannot be determined.
  Future<String?> coreVersion();

  /// Releases everything, and waits for the parts that must not be cut short.
  Future<void> shutdown();

  /// Last-resort synchronous cleanup after [shutdown] could not be awaited.
  void dispose();
}
