/// Windows proxy runtime backed by a supervised sing-box process.
///
/// Supports two modes:
/// - **System proxy mode**: uses a loopback mixed inbound with WinINet, no
///   elevation required.
/// - **TUN mode**: uses a Wintun virtual adapter, requires administrator rights
///   and the Wintun support bundled in sing-box.
///
/// TUN mode needs:
/// 1. Administrator privileges (UAC prompt on first run)
/// 2. sing-box.exe with TUN support enabled
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/config_builder.dart';
import '../models/proxy_state.dart';
import 'app_paths.dart';
import 'config_facts.dart';
import 'core_version.dart';
import 'desktop_runtime.dart';
import 'proxy_controller.dart';
import 'windows_privileges.dart';

class WindowsProxyController extends DesktopRuntime implements ProxyController {
  WindowsProxyController({
    WindowsPrivileges? privileges,
    void Function()? exitProcess,
  })  : _privileges = privileges ?? WindowsPrivileges(),
        _exitProcess = exitProcess ?? (() => exit(0)) {
    // If the previous process was terminated while it owned WinINet, the
    // native runner has a persisted backup. Restore it before the next start;
    // the call is a no-op on a clean launch and on older runners.
    unawaited(_restoreSystemProxy());
  }

  static const _method = MethodChannel(appControlChannel);
  static const _apiHost = '127.0.0.1';
  static const _apiReadyTimeout = Duration(seconds: 12);
  static const _apiRequestTimeout = Duration(seconds: 8);
  static const _selectionConfirmTimeout = Duration(seconds: 3);
  static const _statsPollInterval = Duration(seconds: 1);
  static const _groupsPollInterval = Duration(seconds: 5);

  final WindowsPrivileges _privileges;
  final void Function() _exitProcess;
  final HttpClient _apiClient = HttpClient()..findProxy = _directProxy;

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Timer? _statsPollTimer;
  Timer? _groupsPollTimer;
  File? _configFile;
  int _apiPort = ConfigBuilder.defaultClashApiPort;
  String? _apiSecret;
  int _mixedPort = ConfigBuilder.defaultLocalProxyPort;
  var _usesSystemProxy = false;
  var _usesTun = false;
  var _statsInFlight = false;
  var _groupsInFlight = false;
  int? _lastUploadTotal;
  int? _lastDownloadTotal;
  var _uploadTotal = 0;
  var _downloadTotal = 0;
  var _connections = 0;
  var _memory = 0;

  static String _directProxy(Uri _) => 'DIRECT';

  /// TUN mode requires administrator rights; sing-box carries its Wintun
  /// support in the Windows runtime.
  /// System proxy mode needs no elevation.
  @override
  Future<bool> requestPermission() async {
    if (isDisposed) return false;
    // Permission check happens in start() when we know which mode is requested.
    return true;
  }

  @override
  Future<void> start(String configJson) =>
      enqueueLifecycle(() => _startInternal(configJson));

  Future<void> _startInternal(String configJson) async {
    if (isDisposed) throw StateError('Windows proxy controller is disposed');
    if (_process != null) {
      throw StateError('Windows proxy is already running');
    }

    final session = beginSession();
    emitState(ProxyState(stage: ProxyStage.starting, sessionId: session));
    isStopping = false;
    _lastUploadTotal = null;
    _lastDownloadTotal = null;
    var systemProxyAvailable = true;
    try {
      // A stale marker means an earlier process died without running its
      // shutdown path. Restoring first prevents us from nesting our proxy on
      // top of a previous copy of the app's settings.
      await _restoreSystemProxy();
      if (!isCurrentSession(session)) return;

      final core = _findCore();
      if (core == null) throw _problem(EngineProblem.missing);

      // Before anything is written or started: an older core rejects the 1.12
      // schema this app renders, and its own complaint is a schema dump. Null
      // means the version could not be read at all, which is not grounds to
      // refuse a start.
      final version = await readCoreVersion(core.path);
      if (!isCurrentSession(session)) return;
      if (version != null && !versionAtLeast(version, singBoxMinimumVersion)) {
        throw _problem(EngineProblem.tooOld, version.join('.'));
      }

      final config = _prepareConfig(configJson);
      _applyConfigFacts(
        ConfigFacts.fromMap(Map<Object?, Object?>.from(config)),
      );

      // TUN mode requires administrator rights.
      if (_usesTun && !await _authorizeTun()) {
        return;
      }
      if (!isCurrentSession(session)) return;

      final runtime = await _runtimeDirectory();
      if (!isCurrentSession(session)) return;
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
      if (!isCurrentSession(session)) return;
      if (check.exitCode != 0) {
        // Only the exit code travels. A malformed custom node puts credentials
        // into the engine's diagnostic, so stdout/stderr is deliberately
        // dropped rather than shown or logged.
        throw _problem(EngineProblem.configRejected, '${check.exitCode}');
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
      if (!isCurrentSession(session)) {
        process.kill();
        return;
      }
      _process = process;
      _watchProcess(process, session: session);
      await _trackProcess(process.pid);
      if (!isCurrentSession(session) || !identical(_process, process)) return;

      await _waitForApi(session: session);
      if (isDisposed || !identical(_process, process)) {
        throw StateError('Windows sing-box exited while starting.');
      }
      if (_usesSystemProxy) {
        try {
          await _enableSystemProxy(port: _mixedPort);
        } on StateError catch (error) {
          // The core and its loopback inbound are still healthy. Keep the
          // session alive and expose the missing host-wide coverage instead of
          // tearing down a usable local proxy.
          if (EngineProblem.of(error.message.toString()) !=
              EngineProblem.systemProxyUnavailable) {
            rethrow;
          }
          systemProxyAvailable = false;
          log('system proxy unavailable; local proxy remains available');
        }
      }
      if (!isCurrentSession(session) || !identical(_process, process)) return;
      // The core can exit between the readiness probe and WinINet update. Do
      // not leave a dead loopback proxy behind in that race.
      if (isDisposed || !identical(_process, process)) {
        await _restoreSystemProxy();
        throw StateError('Windows sing-box exited while starting.');
      }
      _startPolling(session: session);
      if (!isDisposed && sessionId == session && identical(_process, process)) {
        emitState(
          ProxyState(
            stage: ProxyStage.connected,
            since: DateTime.now(),
            sessionId: session,
            coverage: _usesTun
                ? ProxyCoverage.tun
                : _usesSystemProxy
                    ? systemProxyAvailable
                        ? ProxyCoverage.systemProxy
                        : ProxyCoverage.systemProxyUnavailable
                    : ProxyCoverage.localProxy,
          ),
        );
      }
    } on Object catch (error) {
      await _stopInternal(reportState: false);
      final message = _friendlyError(error);
      emitError(message, session: session);
      rethrow;
    }
  }

  @override
  Future<void> stop() => enqueueLifecycle(_stopInternalPublic);

  Future<void> _stopInternalPublic() async {
    if (isDisposed) return;
    emitState(ProxyState(
      stage: ProxyStage.stopping,
      sessionId: sessionId,
    ));
    await _stopInternal(reportState: false);
    if (!isDisposed) emitState(ProxyState(sessionId: sessionId));
  }

  @override
  Future<void> clearLogs() async {
    // Standalone sing-box writes to stdout/stderr; there is no libbox command
    // log buffer to clear. AppState clears its bounded viewer synchronously.
  }

  @override
  Future<void> reload(String configJson) => enqueueLifecycle(() async {
        if (_process == null) throw StateError('Windows proxy is not running');
        // The standalone binary's Clash API deliberately does not reload a
        // full config. Restarting keeps route/DNS changes deterministic and
        // ensures the previous WinINet settings are restored between
        // generations.
        await _stopInternal(reportState: false);
        await _startInternal(configJson);
      });

  @override
  Future<void> selectOutbound(String outboundTag) async {
    _requireRunning();
    await _apiRequest(
      'PUT',
      '/proxies/${Uri.encodeComponent(ConfigTags.proxy)}',
      body: jsonEncode({'name': outboundTag}),
    );

    // Do not report success just because the API accepted the PUT. Confirm the
    // selector's `now` value so AppState cannot commit a node that the running
    // engine did not actually start using.
    final deadline = DateTime.now().add(_selectionConfirmTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final selected = await _selectedOutbound();
      if (selected == outboundTag) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('sing-box did not confirm the selected node');
  }

  Future<String?> _selectedOutbound() async {
    final body = await _apiRequest('GET', '/proxies');
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final proxies = decoded['proxies'];
    if (proxies is! Map) return null;
    final group = proxies[ConfigTags.proxy];
    if (group is! Map) return null;
    return group['now']?.toString();
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
    emitGroup(
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
  Future<void> shutdown() async {
    // Order matters. Stopping first lets sing-box close its inbounds and flush
    // its cache, and the _stopInternal inside it is what puts the WinINet proxy
    // settings back — the step dispose can start but not wait for.
    try {
      await enqueueLifecycle(() async {
        if (_process != null) {
          await _stopInternal(reportState: false);
        } else {
          // No engine of ours running, but an earlier unclean exit may still
          // have left WinINet pointed at that port. Cheap to be sure.
          await _restoreSystemProxy();
        }
      });
    } on Object {
      // Quitting must not hang on a stubborn engine. dispose below still kills
      // it, the Job Object reaps whatever survives that, and the restore on the
      // next launch is the backstop for the settings.
    }
    dispose();
  }

  @override
  void dispose() {
    if (!markDisposed()) return;
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
    _apiClient.close(force: true);
    closeStreams();
  }

  // -------------------------------------------------------------- lifecycle

  void _watchProcess(Process process, {required int session}) {
    _stdoutSubscription = pipeLines(process.stdout);
    _stderrSubscription = pipeLines(process.stderr);
    unawaited(
      process.exitCode.then((code) => _processExited(
            process,
            code,
            session: session,
          )),
    );
  }

  void _processExited(Process process, int code, {required int session}) {
    if (!identical(_process, process) || sessionId != session) return;
    final stopping = isStopping;
    _process = null;
    _cancelPolling();
    unawaited(_restoreSystemProxy());
    final file = _configFile;
    _configFile = null;
    unawaited(_deleteFile(file));
    if (isDisposed || stopping) return;

    emitError(
      'sing-box stopped unexpectedly (exit $code).',
      session: session,
    );
  }

  Future<void> _stopInternal({required bool reportState}) async {
    isStopping = true;
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
    if (reportState && !isDisposed) {
      emitState(ProxyState(sessionId: sessionId));
    }
    isStopping = false;
  }

  void _startPolling({required int session}) {
    _cancelPolling();
    _statsPollTimer = Timer.periodic(
      _statsPollInterval,
      (_) => unawaited(_pollStats(session: session)),
    );
    _groupsPollTimer = Timer.periodic(
      _groupsPollInterval,
      (_) => unawaited(_pollGroups(session: session)),
    );
    unawaited(_pollStats(session: session));
    unawaited(_pollGroups(session: session));
  }

  void _cancelPolling() {
    _statsPollTimer?.cancel();
    _statsPollTimer = null;
    _groupsPollTimer?.cancel();
    _groupsPollTimer = null;
    _statsInFlight = false;
    _groupsInFlight = false;
  }

  // --------------------------------------------------------------- API bridge

  Future<void> _waitForApi({required int session}) async {
    final deadline = DateTime.now().add(_apiReadyTimeout);
    while (!isDisposed &&
        sessionId == session &&
        _process != null &&
        DateTime.now().isBefore(deadline)) {
      try {
        await _apiRequest(
          'GET',
          '/version',
          timeout: const Duration(milliseconds: 700),
        );
        return;
      } on Object {
        // Expected while the core is still binding its listener. Only running
        // out of deadline is a failure, and it reports the same either way.
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (sessionId != session || _process == null) {
      throw StateError('Windows sing-box exited while starting.');
    }
    throw _problem(EngineProblem.apiTimeout);
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
    final uri = Uri(
      scheme: 'http',
      host: _apiHost,
      port: _apiPort,
      path: path,
      queryParameters: query,
    );
    final deadline = DateTime.now().add(timeout);
    Duration remaining() {
      final value = deadline.difference(DateTime.now());
      if (value <= Duration.zero) {
        throw TimeoutException('control API timed out');
      }
      return value;
    }

    final request = await _apiClient.openUrl(method, uri).timeout(remaining());
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body is String ? body : jsonEncode(body));
    }
    final response = await request.close().timeout(remaining());
    final text =
        await response.transform(utf8.decoder).join().timeout(remaining());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'control API returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    return text;
  }

  Future<void> _pollStats({required int session}) async {
    if (isDisposed ||
        sessionId != session ||
        _process == null ||
        _statsInFlight) {
      return;
    }
    _statsInFlight = true;
    try {
      final body = await _apiRequest('GET', '/connections');
      final decoded = jsonDecode(body);
      if (decoded is! Map || isDisposed || sessionId != session) return;
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
      emitTraffic(ProxyTraffic(
        uplink: uploadDelta,
        downlink: downloadDelta,
        uplinkTotal: _uploadTotal,
        downlinkTotal: _downloadTotal,
        connectionsIn: _connections,
        connectionsOut: _connections,
        memory: _memory,
      ));
    } on Object {
      // A stopped process and a closing API socket are expected during
      // disconnect. Avoid turning a one-second poll into a log flood.
    } finally {
      _statsInFlight = false;
    }
  }

  Future<void> _pollGroups({required int session}) async {
    if (isDisposed ||
        sessionId != session ||
        _process == null ||
        _groupsInFlight) {
      return;
    }
    _groupsInFlight = true;
    try {
      final body = await _apiRequest('GET', '/proxies');
      final decoded = jsonDecode(body);
      if (decoded is! Map ||
          decoded['proxies'] is! Map ||
          isDisposed ||
          sessionId != session) {
        return;
      }
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
        emitGroup(
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
    if (isDisposed ||
        _process == null ||
        currentState.stage != ProxyStage.connected) {
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
    var usesTun = false;
    final inbounds = <Map<String, dynamic>>[];
    for (final raw in rawInbounds) {
      if (raw is! Map) continue;
      final inbound = Map<String, dynamic>.from(raw);
      final type = inbound['type']?.toString().toLowerCase();
      if (type == 'tun') {
        // Keep the TUN inbound until authorization has decided whether this
        // process may start the config.
        usesTun = true;
        final platform = inbound['platform'];
        if (platform is Map) {
          final httpProxy = platform['http_proxy'];
          if (httpProxy is Map && httpProxy['enabled'] == true) {
            useSystemProxy = true;
          }
        }
        // Keep the TUN inbound until authorization has completed. Removing it
        // here would make a successful UAC relaunch start the fallback mixed
        // config instead of the TUN config it was asked to run.
        inbounds.add(inbound);
        continue;
      }
      if (type == 'mixed' || type == 'http') {
        if (inbound['set_system_proxy'] == true) useSystemProxy = true;
        inbound.remove('set_system_proxy');
      }
      inbounds.add(inbound);
    }

    // A custom config may omit the loopback inbound; keep the Clash API and the
    // app's local-proxy path usable by adding the safe loopback fallback.
    if (!inbounds.any(
      (item) => item['type']?.toString().toLowerCase() == 'mixed',
    )) {
      inbounds.add({
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': ConfigBuilder.defaultLocalProxyPort,
      });
    }
    config['inbounds'] = inbounds;
    // With no TUN inbound, this is the Windows system-proxy mode and WinINet
    // must be pointed at the loopback listener automatically. In TUN mode the
    // optional platform.http_proxy block controls whether WinINet is also
    // enabled for applications that ignore the virtual adapter.
    _usesSystemProxy = useSystemProxy || !usesTun;
    _usesTun = usesTun;
    return config;
  }

  /// Exposes the Windows config adaptation to unit tests without starting a
  /// real sing-box process or touching WinINet.
  @visibleForTesting
  Map<String, dynamic> prepareConfigForTests(String configJson) =>
      _prepareConfig(configJson);

  /// Whether the most recently prepared config should update WinINet.
  @visibleForTesting
  bool get usesSystemProxyForTests => _usesSystemProxy;

  void _applyConfigFacts(ConfigFacts facts) {
    _apiPort = facts.clashPort;
    _apiSecret = facts.clashSecret;
    _mixedPort = facts.mixedPort;
    _usesTun = facts.hasTun;
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

  Future<bool> _authorizeTun() async {
    emitState(ProxyState(
      stage: ProxyStage.requestingPermission,
      sessionId: sessionId,
    ));

    final status = await _privileges.requestTunPrivileges();

    switch (status) {
      case TunAuthorizationStatus.granted:
        emitState(ProxyState(
          stage: ProxyStage.starting,
          sessionId: sessionId,
        ));
        return true;

      case TunAuthorizationStatus.declined:
        // No detail: here the fix is the UAC prompt, not a capability on a
        // path, so naming the binary would only be noise. See noticeText.
        fail(EngineProblem.unprivileged);
        return false;

      case TunAuthorizationStatus.relaunching:
        // The elevated child waits for this process to disappear, then claims
        // the single-instance socket and starts the same persisted settings.
        emitState(ProxyState(sessionId: sessionId));
        unawaited(_exitAfterElevation());
        return false;

      case TunAuthorizationStatus.failed:
        fail(EngineProblem.elevationFailed);
        return false;
    }
  }

  Future<void> _exitAfterElevation() async {
    // Let the successful MethodChannel reply reach the runner before
    // terminating this process. The child has a bounded socket handoff wait.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!isDisposed) _exitProcess();
  }

  Future<void> _enableSystemProxy({required int port}) async {
    try {
      await _method.invokeMethod<void>('setSystemProxy', {
        'server': '127.0.0.1:$port',
      });
    } on Object {
      throw _problem(EngineProblem.systemProxyUnavailable);
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

  /// A classified failure as a throwable, for the paths inside `_startInternal`
  /// that unwind through its catch rather than reporting directly.
  ///
  /// [_friendlyError] passes a [StateError]'s message straight to [emitError],
  /// so the encoded marker survives the trip and the UI still localises it. The
  /// reporting counterpart is the base class's `fail`.
  static StateError _problem(EngineProblem problem, [String? detail]) =>
      StateError(problem.encode(detail));

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
