/// Platform-neutral proxy runtime boundary.
///
/// The UI talks only to [ProxyController]. Android is backed by a VpnService
/// running sing-box via libbox; Windows supervises a bundled standalone core
/// for its loopback system-proxy runtime.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/proxy_state.dart';
import 'app_paths.dart';
import 'windows_proxy_controller.dart';

abstract interface class ProxyController {
  Stream<ProxyState> get states;
  Stream<ProxyTraffic> get traffic;
  Stream<ProxyLogEntry> get logs;

  /// Outbound group updates, including each member's URL-test delay.
  ///
  /// The engine pushes these on its own schedule as well as after [urlTest],
  /// so a listener sees results trickle in rather than one final answer.
  Stream<ProxyGroup> get groups;

  ProxyState get currentState;

  /// Requests the platform VPN permission. Returns true when granted.
  Future<bool> requestPermission();

  /// Starts the tunnel with [configJson] (a rendered sing-box config).
  Future<void> start(String configJson);

  Future<void> stop();

  /// Clears the engine's in-memory log buffer.
  ///
  /// The UI keeps its own bounded copy, so implementations should treat this
  /// as best-effort when the tunnel is not running.
  Future<void> clearLogs();

  /// Applies a new config without tearing the tunnel down.
  Future<void> reload(String configJson);

  /// Selects [outboundTag] inside the `selector` group at runtime.
  Future<void> selectOutbound(String outboundTag);

  /// Asks the engine to URL-test every member of the main selector group.
  ///
  /// Returns as soon as the request is handed over: the delays arrive later on
  /// [groups]. Throws when the tunnel is not running, so callers can fall back
  /// to probing the nodes themselves.
  Future<void> urlTest();

  /// Version of the bundled proxy core, or null when it cannot be determined.
  Future<String?> coreVersion();

  void dispose();
}

/// Android implementation backed by `SingBoxVpnService` + libbox.
class AndroidProxyController implements ProxyController {
  AndroidProxyController() {
    _events.receiveBroadcastStream().listen(_onEvent, onError: _onEventError);
    // Recover state if the service outlived the Flutter engine.
    _method.invokeMethod<Map<Object?, Object?>>('status').then(
      (value) {
        if (value != null) _applyStatus(value);
      },
      onError: (_) {},
    );
  }

  static const _method = MethodChannel(appControlChannel);
  static const _events = EventChannel('singbox/events');

  final _stateController = StreamController<ProxyState>.broadcast();
  final _trafficController = StreamController<ProxyTraffic>.broadcast();
  final _logController = StreamController<ProxyLogEntry>.broadcast();
  final _groupController = StreamController<ProxyGroup>.broadcast();

  var _state = ProxyState.disconnected;

  @override
  Stream<ProxyState> get states => _stateController.stream;

  @override
  Stream<ProxyTraffic> get traffic => _trafficController.stream;

  @override
  Stream<ProxyLogEntry> get logs => _logController.stream;

  @override
  Stream<ProxyGroup> get groups => _groupController.stream;

  @override
  ProxyState get currentState => _state;

  void _emit(ProxyState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final map = event.cast<Object?, Object?>();
    switch (map['type']) {
      case 'status':
        _applyStatus(map);
      case 'traffic':
        if (!_trafficController.isClosed) {
          _trafficController.add(ProxyTraffic.fromMap(map));
        }
      case 'log':
        if (!_logController.isClosed) {
          _logController.add(ProxyLogEntry(
            message: (map['message'] ?? '').toString(),
            at: DateTime.now(),
          ));
        }
      case 'groups':
        final groups = map['groups'];
        if (groups is! List || _groupController.isClosed) return;
        for (final group in groups) {
          if (group is Map) {
            _groupController.add(ProxyGroup.fromMap(group.cast()));
          }
        }
    }
  }

  void _applyStatus(Map<Object?, Object?> map) {
    final stage = switch (map['stage']) {
      'connected' => ProxyStage.connected,
      'starting' => ProxyStage.starting,
      'stopping' => ProxyStage.stopping,
      'error' => ProxyStage.error,
      _ => ProxyStage.disconnected,
    };
    final sinceMillis = map['since'];
    _emit(ProxyState(
      stage: stage,
      message: map['message']?.toString(),
      since: stage == ProxyStage.connected && sinceMillis is num
          ? DateTime.fromMillisecondsSinceEpoch(sinceMillis.toInt())
          : null,
    ));
  }

  void _onEventError(Object error) {
    _emit(ProxyState(stage: ProxyStage.error, message: error.toString()));
  }

  @override
  Future<bool> requestPermission() async {
    _emit(const ProxyState(stage: ProxyStage.requestingPermission));
    try {
      final granted = await _method.invokeMethod<bool>('requestPermission');
      if (granted != true) _emit(ProxyState.disconnected);
      return granted ?? false;
    } on PlatformException catch (error) {
      _emit(ProxyState(
          stage: ProxyStage.error, message: error.message ?? error.code));
      return false;
    }
  }

  @override
  Future<void> start(String configJson) async {
    _emit(const ProxyState(stage: ProxyStage.starting));
    try {
      await _method.invokeMethod<void>('start', {'config': configJson});
    } on PlatformException catch (error) {
      _emit(ProxyState(
          stage: ProxyStage.error, message: error.message ?? error.code));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _emit(const ProxyState(stage: ProxyStage.stopping));
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (error) {
      _emit(ProxyState(
          stage: ProxyStage.error, message: error.message ?? error.code));
    }
  }

  @override
  Future<void> clearLogs() async {
    try {
      await _method.invokeMethod<void>('clearLogs');
    } on PlatformException {
      // Clearing a local viewer must still work when the service has already
      // gone away; the native buffer is only a secondary copy.
    }
  }

  @override
  Future<void> reload(String configJson) async {
    await _method.invokeMethod<void>('reload', {'config': configJson});
  }

  @override
  Future<void> selectOutbound(String outboundTag) async {
    await _method.invokeMethod<void>('selectOutbound', {'tag': outboundTag});
  }

  @override
  Future<void> urlTest() async {
    await _method.invokeMethod<void>('urlTest');
  }

  @override
  Future<String?> coreVersion() async {
    try {
      return await _method.invokeMethod<String>('version');
    } on PlatformException {
      return null;
    }
  }

  @override
  void dispose() {
    _stateController.close();
    _trafficController.close();
    _logController.close();
    _groupController.close();
  }
}

/// Placeholder for platforms without a runtime yet. Keeps the UI usable and
/// reports an actionable message instead of silently doing nothing.
class UnsupportedProxyController implements ProxyController {
  UnsupportedProxyController(this.reason);

  final String reason;

  final _stateController = StreamController<ProxyState>.broadcast();

  var _state = ProxyState.disconnected;

  @override
  Stream<ProxyState> get states => _stateController.stream;

  @override
  Stream<ProxyTraffic> get traffic => const Stream.empty();

  @override
  Stream<ProxyLogEntry> get logs => const Stream.empty();

  @override
  Stream<ProxyGroup> get groups => const Stream.empty();

  @override
  ProxyState get currentState => _state;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> start(String configJson) async {
    _state = ProxyState(stage: ProxyStage.error, message: reason);
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  @override
  Future<void> stop() async {
    _state = ProxyState.disconnected;
    if (!_stateController.isClosed) _stateController.add(_state);
  }

  @override
  Future<void> clearLogs() async {}

  @override
  Future<void> reload(String configJson) async {}

  @override
  Future<void> selectOutbound(String outboundTag) async {}

  @override
  Future<void> urlTest() async {}

  @override
  Future<String?> coreVersion() async => null;

  @override
  void dispose() => _stateController.close();
}

ProxyController createProxyController() {
  if (Platform.isAndroid) return AndroidProxyController();
  if (Platform.isWindows) return WindowsProxyController();
  return UnsupportedProxyController(
    'The ${Platform.operatingSystem} runtime is not implemented yet. '
    'Config rendering and node management still work.',
  );
}
