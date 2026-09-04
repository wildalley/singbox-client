/// Placeholder runtime for platforms without an engine integration.
library;

import 'dart:async';

import '../models/proxy_state.dart';
import 'proxy_controller_base.dart';

/// Keeps the UI usable and reports an actionable message instead of silently
/// doing nothing on an unsupported host platform.
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
  Future<void> shutdown() async => dispose();

  @override
  void dispose() => _stateController.close();
}
