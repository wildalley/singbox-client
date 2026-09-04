/// Android proxy runtime backed by `SingBoxVpnService` and libbox.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../models/proxy_state.dart';
import 'app_paths.dart';
import 'proxy_controller_base.dart';

/// Android implementation backed by the foreground VPN service.
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
      sessionId: (map['session'] as num?)?.toInt(),
      coverage: stage == ProxyStage.connected ? ProxyCoverage.tun : null,
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
  Future<void> shutdown() async {
    // The tunnel belongs to a foreground service with its own lifecycle. The
    // Flutter engine going away is not a reason to drop the VPN.
    dispose();
  }

  @override
  void dispose() {
    _stateController.close();
    _trafficController.close();
    _logController.close();
    _groupController.close();
  }
}
