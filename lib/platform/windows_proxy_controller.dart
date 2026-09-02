/// Windows proxy runtime backed by a supervised sing-box process.
///
/// The first desktop runtime intentionally uses the loopback mixed inbound
/// rather than TUN. It gives Windows applications that honour WinINet a real
/// proxy without requiring an elevated helper or a Wintun driver. The generated
/// config still contains the Android TUN inbound; it is removed here before the
/// standalone core is started because a desktop process cannot open it safely
/// from the Flutter UI process yet.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../data/config_builder.dart';
import '../models/proxy_state.dart';
import 'app_paths.dart';
import 'proxy_controller.dart';

class WindowsProxyController implements ProxyController {
  WindowsProxyController() {
    // If the previous process was terminated while it owned WinINet, the
    // native runner has a persisted backup. Restore it before the next start;
    // the call is a no-op on a clean launch and on older runners.
    unawaited(_restoreSystemProxy());
  }

  static const _method = MethodChannel(appControlChannel);
  static const _apiHost = '127.0.0.1';
  static const _apiReadyTimeout = Duration(seconds: 12);
  static const _apiRequestTimeout = Duration(seconds: 8);
  static const _pollInterval = Duration(seconds: 1);

  final _stateController = StreamController<ProxyState>.broadcast();
  final _trafficController = StreamController<ProxyTraffic>.broadcast();
  final _logController = StreamController<ProxyLogEntry>.broadcast();
  final _groupController = StreamController<ProxyGroup>.broadcast();

  var _state = ProxyState.disconnected;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Timer? _pollTimer;
  File? _configFile;
  int _apiPort = ConfigBuilder.clashApiPort;
  String? _apiSecret;
  var _usesSystemProxy = false;
  var _stopping = false;
  var _disposed = false;
  var _statsInFlight = false;
  var _groupsInFlight = false;
  int? _lastUploadTotal;
  int? _lastDownloadTotal;
  var _uploadTotal = 0;
  var _downloadTotal = 0;
  var _connections = 0;
  var _memory = 0;

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

  /// The loopback MVP does not need administrator permission.
  @override
  Future<bool> requestPermission() async => !_disposed;

  @override
  Future<void> start(String configJson) async {
    if (_disposed) throw StateError('Windows proxy controller is disposed');
    if (_process != null) {
      throw StateError('Windows proxy is already running');
    }

    _emitState(const ProxyState(stage: ProxyStage.starting));
    _stopping = false;
    _lastUploadTotal = null;
    _lastDownloadTotal = null;
    try {
      // A stale marker means an earlier process died without running its
      // shutdown path. Restoring first prevents us from nesting our proxy on
      // top of a previous copy of the app's settings.
      await _restoreSystemProxy();

      final core = _findCore();
      if (core == null) {
        throw StateError(
          'Windows sing-box runtime is missing sing-box.exe. '
          'Reinstall the Windows bundle or set SINGBOX_PATH for development.',
        );
      }

      final config = _prepareConfig(configJson);
      _extractApiSettings(config);

      final runtime = await _runtimeDirectory();
      final file = File(
        '${runtime.path}${Platform.pathSeparator}config-$pid.json',
      );
      _configFile = file;
      await file.writeAsString(jsonEncode(config), flush: true);

      final check = await Process.run(
        core.path,
        ['check', '-c', file.path],
        runInShell: false,
      ).timeout(_apiReadyTimeout);
      if (check.exitCode != 0) {
        // Do not surface stdout/stderr here: a malformed custom node can put
        // credentials into an engine diagnostic. The full process output is
        // still available in the log stream after a successful start.
        throw StateError(
          'Windows sing-box rejected the generated configuration '
          '(exit ${check.exitCode}).',
        );
      }

      final process = await Process.start(
        core.path,
        ['run', '-c', file.path],
        workingDirectory: runtime.path,
        runInShell: false,
        // Keep the process attached so exitCode can supervise it and the
        // shutdown path can wait for a graceful SIGINT. The runner's native
        // OnDestroy still restores WinINet if the UI closes unexpectedly.
        mode: ProcessStartMode.normal,
      );
      _process = process;
      _watchProcess(process);
      await _trackProcess(process.pid);

      await _waitForApi();
      if (_disposed || !identical(_process, process)) {
        throw StateError('Windows sing-box exited while starting.');
      }
      if (_usesSystemProxy) await _enableSystemProxy();
      // The core can exit between the readiness probe and WinINet update. Do
      // not leave a dead loopback proxy behind in that race.
      if (_disposed || !identical(_process, process)) {
        await _restoreSystemProxy();
        throw StateError('Windows sing-box exited while starting.');
      }
      _startPolling();
      if (!_disposed && identical(_process, process)) {
        _emitState(
          ProxyState(stage: ProxyStage.connected, since: DateTime.now()),
        );
      }
    } on Object catch (error) {
      await _stopInternal(emitState: false);
      final message = _friendlyError(error);
      _emitState(ProxyState(stage: ProxyStage.error, message: message));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _emitState(const ProxyState(stage: ProxyStage.stopping));
    await _stopInternal(emitState: false);
    _emitState(ProxyState.disconnected);
  }

  @override
  Future<void> clearLogs() async {
    // Standalone sing-box writes to stdout/stderr; there is no libbox command
    // log buffer to clear. AppState clears its bounded viewer synchronously.
  }

  @override
  Future<void> reload(String configJson) async {
    if (_process == null) throw StateError('Windows proxy is not running');
    // The standalone binary's Clash API deliberately does not reload a full
    // config. Restarting keeps route/DNS changes deterministic and ensures the
    // previous WinINet settings are restored between generations.
    await stop();
    await start(configJson);
  }

  @override
  Future<void> selectOutbound(String outboundTag) async {
    _requireRunning();
    await _apiRequest(
      'PUT',
      '/proxies/${Uri.encodeComponent(ConfigTags.proxy)}',
      body: jsonEncode({'name': outboundTag}),
    );
  }

  @override
  Future<void> urlTest() async {
    _requireRunning();
    final body = await _apiRequest(
      'GET',
      '/group/${Uri.encodeComponent(ConfigTags.proxy)}/delay',
      query: const {
        'url': 'https://www.gstatic.com/generate_204',
        'timeout': '10000',
      },
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map) return;
    final delays = <String, int>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is num && value > 0) {
        delays[entry.key.toString()] = value.toInt();
      }
    }
    _emitGroup(
      ProxyGroup(tag: ConfigTags.proxy, selected: '', delays: delays),
    );
  }

  @override
  Future<String?> coreVersion() async {
    final core = _findCore();
    if (core == null) return null;
    try {
      final result = await Process.run(
        core.path,
        ['version'],
        runInShell: false,
      ).timeout(const Duration(seconds: 4));
      if (result.exitCode != 0) return null;
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return null;
      return output.split(RegExp(r'\r?\n')).first.trim();
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelPolling();
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        process.kill();
      } on Object {
        // The process may already have exited between the read and the kill.
      }
    }
    unawaited(_restoreSystemProxy());
    final file = _configFile;
    _configFile = null;
    unawaited(_deleteFile(file));
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _stateController.close();
    _trafficController.close();
    _logController.close();
    _groupController.close();
  }

  // -------------------------------------------------------------- lifecycle

  void _watchProcess(Process process) {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_emitLog, onError: (_) {});
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_emitLog, onError: (_) {});
    unawaited(process.exitCode.then((code) => _processExited(process, code)));
  }

  void _processExited(Process process, int code) {
    if (!identical(_process, process)) return;
    final stopping = _stopping;
    _process = null;
    _cancelPolling();
    unawaited(_restoreSystemProxy());
    final file = _configFile;
    _configFile = null;
    unawaited(_deleteFile(file));
    if (_disposed || stopping) return;

    _emitState(
      ProxyState(
        stage: ProxyStage.error,
        message: 'sing-box stopped unexpectedly (exit $code).',
      ),
    );
  }

  Future<void> _stopInternal({required bool emitState}) async {
    _stopping = true;
    _cancelPolling();
    final process = _process;
    if (process != null) {
      try {
        // sing-box handles SIGINT as a graceful shutdown and restores any
        // resources it owns. A hard kill below is only the escape hatch.
        process.kill(ProcessSignal.sigint);
      } on Object {
        try {
          process.kill(ProcessSignal.sigterm);
        } on Object {
          // It may have exited already.
        }
      }
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on Object {
        try {
          process.kill();
        } on Object {
          // Ignore a race with process exit.
        }
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on Object {
          // The OS will reap it; do not keep the UI blocked forever.
        }
      }
    }

    if (identical(_process, process)) _process = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    await _restoreSystemProxy();
    final file = _configFile;
    _configFile = null;
    await _deleteFile(file);
    if (emitState && !_disposed) _emitState(ProxyState.disconnected);
    _stopping = false;
  }

  void _startPolling() {
    _cancelPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_pollStats());
      unawaited(_pollGroups());
    });
    unawaited(_pollStats());
    unawaited(_pollGroups());
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _statsInFlight = false;
    _groupsInFlight = false;
  }

  // --------------------------------------------------------------- API bridge

  Future<void> _waitForApi() async {
    final deadline = DateTime.now().add(_apiReadyTimeout);
    Object? lastError;
    while (
        !_disposed && _process != null && DateTime.now().isBefore(deadline)) {
      try {
        await _apiRequest(
          'GET',
          '/version',
          timeout: const Duration(milliseconds: 700),
        );
        return;
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (_process == null) {
      throw StateError('Windows sing-box exited while starting.');
    }
    throw StateError(
      lastError == null
          ? 'Windows sing-box did not expose its control API in time.'
          : 'Windows sing-box did not become ready in time.',
    );
  }

  Future<String> _apiRequest(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = _apiRequestTimeout,
  }) async {
    final secret = _apiSecret;
    if (secret == null || secret.isEmpty) {
      throw StateError('Windows proxy control API is not configured.');
    }
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final uri = Uri(
        scheme: 'http',
        host: _apiHost,
        port: _apiPort,
        path: path,
        queryParameters: query,
      );
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body is String ? body : jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final text =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'control API returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _pollStats() async {
    if (_disposed || _process == null || _statsInFlight) return;
    _statsInFlight = true;
    try {
      final body = await _apiRequest('GET', '/connections');
      final decoded = jsonDecode(body);
      if (decoded is! Map || _disposed) return;
      final upload = _intValue(decoded['uploadTotal']);
      final download = _intValue(decoded['downloadTotal']);
      final uploadDelta = _lastUploadTotal == null
          ? 0
          : (upload - _lastUploadTotal!).clamp(0, upload).toInt();
      final downloadDelta = _lastDownloadTotal == null
          ? 0
          : (download - _lastDownloadTotal!).clamp(0, download).toInt();
      _lastUploadTotal = upload;
      _lastDownloadTotal = download;
      _uploadTotal = upload;
      _downloadTotal = download;
      _connections = decoded['connections'] is List
          ? (decoded['connections'] as List).length
          : 0;
      _memory = _intValue(decoded['memory']);
      if (!_trafficController.isClosed) {
        _trafficController.add(
          ProxyTraffic(
            uplink: uploadDelta,
            downlink: downloadDelta,
            uplinkTotal: _uploadTotal,
            downlinkTotal: _downloadTotal,
            connectionsIn: _connections,
            connectionsOut: _connections,
            memory: _memory,
          ),
        );
      }
    } on Object {
      // A stopped process and a closing API socket are expected during
      // disconnect. Avoid turning a one-second poll into a log flood.
    } finally {
      _statsInFlight = false;
    }
  }

  Future<void> _pollGroups() async {
    if (_disposed || _process == null || _groupsInFlight) return;
    _groupsInFlight = true;
    try {
      final body = await _apiRequest('GET', '/proxies');
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['proxies'] is! Map) return;
      final proxies = decoded['proxies'] as Map;
      for (final entry in proxies.entries) {
        final tag = entry.key.toString();
        final info = entry.value;
        if (info is! Map) continue;
        final type = info['type']?.toString().toLowerCase() ?? '';
        if (!type.contains('selector') &&
            !type.contains('urltest') &&
            !type.contains('fallback')) {
          continue;
        }
        final members = info['all'];
        if (members is! List) continue;
        final delays = <String, int>{};
        for (final member in members) {
          final memberInfo = proxies[member];
          if (memberInfo is! Map) continue;
          final history = memberInfo['history'];
          if (history is! List || history.isEmpty) continue;
          final last = history.last;
          if (last is Map) {
            final delay = _intValue(last['delay']);
            if (delay > 0) delays[member.toString()] = delay;
          }
        }
        _emitGroup(
          ProxyGroup(
            tag: tag,
            selected: info['now']?.toString() ?? '',
            delays: delays,
          ),
        );
      }
    } on Object {
      // See [_pollStats]. The next tick retries without retaining an error.
    } finally {
      _groupsInFlight = false;
    }
  }

  void _requireRunning() {
    if (_disposed || _process == null || _state.stage != ProxyStage.connected) {
      throw StateError('Windows proxy is not connected');
    }
  }

  // --------------------------------------------------------------- config

  Map<String, dynamic> _prepareConfig(String configJson) {
    final decoded = jsonDecode(configJson);
    if (decoded is! Map) {
      throw const FormatException('config must be an object');
    }
    final config = Map<String, dynamic>.from(decoded);
    final rawInbounds = config['inbounds'];
    if (rawInbounds is! List) {
      throw const FormatException('config has no inbounds');
    }

    var useSystemProxy = false;
    final inbounds = <Map<String, dynamic>>[];
    for (final raw in rawInbounds) {
      if (raw is! Map) continue;
      final inbound = Map<String, dynamic>.from(raw);
      final type = inbound['type']?.toString().toLowerCase();
      if (type == 'tun') {
        final platform = inbound['platform'];
        if (platform is Map) {
          final httpProxy = platform['http_proxy'];
          if (httpProxy is Map && httpProxy['enabled'] == true) {
            useSystemProxy = true;
          }
        }
        continue;
      }
      if (type == 'mixed' || type == 'http') {
        if (inbound['set_system_proxy'] == true) useSystemProxy = true;
        inbound.remove('set_system_proxy');
      }
      inbounds.add(inbound);
    }

    if (!inbounds.any((item) => item['type']?.toString() == 'mixed')) {
      inbounds.add({
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': ConfigBuilder.localProxyPort,
      });
    }
    config['inbounds'] = inbounds;
    _usesSystemProxy = useSystemProxy;
    return config;
  }

  void _extractApiSettings(Map<String, dynamic> config) {
    final experimental = config['experimental'];
    final clash = experimental is Map ? experimental['clash_api'] : null;
    if (clash is! Map) {
      throw const FormatException('config has no Clash API');
    }
    final secret = clash['secret']?.toString();
    if (secret == null || secret.isEmpty) {
      throw const FormatException('config has no Clash API secret');
    }
    _apiSecret = secret;
    final external = clash['external_controller']?.toString() ?? '';
    final portMatch = RegExp(r':(\d+)(?:/)?$').firstMatch(external);
    _apiPort =
        int.tryParse(portMatch?.group(1) ?? '') ?? ConfigBuilder.clashApiPort;
  }

  // ----------------------------------------------------------- Windows host

  File? _findCore() {
    final candidates = <String>[];
    final override = Platform.environment['SINGBOX_PATH'];
    if (override != null && override.trim().isNotEmpty) {
      candidates.add(override.trim());
    }
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    candidates.add(
      '$executableDir${Platform.pathSeparator}sing-box.exe',
    );
    candidates.add(
      '${Directory.current.path}${Platform.pathSeparator}sing-box.exe',
    );
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) return file.absolute;
    }
    return null;
  }

  Future<Directory> _runtimeDirectory() async {
    final base = await appDataDirectory();
    final path = base ??
        '${Directory.current.path}${Platform.pathSeparator}.singbox-client';
    final directory = Directory('$path${Platform.pathSeparator}runtime');
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _enableSystemProxy() async {
    try {
      await _method.invokeMethod<void>('setSystemProxy', {
        'server': '127.0.0.1:${ConfigBuilder.localProxyPort}',
      });
    } on Object {
      throw StateError('Windows system proxy could not be enabled.');
    }
  }

  Future<void> _trackProcess(int processId) async {
    try {
      await _method.invokeMethod<void>('trackProcess', {'pid': processId});
    } on Object {
      throw StateError('Windows sing-box process could not be supervised.');
    }
  }

  Future<void> _restoreSystemProxy() async {
    try {
      await _method.invokeMethod<void>('restoreSystemProxy');
    } on Object {
      // Older runners and non-Windows test hosts simply have no method. The
      // process still works with the loopback inbound for manual clients.
    }
  }

  void _emitState(ProxyState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  void _emitLog(String line) {
    if (_disposed || _logController.isClosed || line.isEmpty) return;
    _logController.add(ProxyLogEntry(message: line, at: DateTime.now()));
  }

  void _emitGroup(ProxyGroup group) {
    if (!_disposed && !_groupController.isClosed) _groupController.add(group);
  }

  static int _intValue(Object? value) => switch (value) {
        int item => item,
        num item => item.toInt(),
        _ => int.tryParse(value?.toString() ?? '') ?? 0,
      };

  static String _friendlyError(Object error) => switch (error) {
        StateError(message: final message) => message.toString(),
        FormatException(message: final message) => message.toString(),
        TimeoutException() => 'Windows sing-box operation timed out.',
        _ => 'Windows sing-box failed to start.',
      };

  static Future<void> _deleteFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // The next start overwrites the per-process file; retaining it is not a
      // reason to block a disconnect.
    }
  }

  int get pid => _process?.pid ?? DateTime.now().microsecondsSinceEpoch;
}
