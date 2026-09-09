/// Linux runtime: supervises a `sing-box` process and drives it over the Clash
/// API.
///
/// Android runs the engine in-process through libbox, which is a gomobile
/// JNI artifact and exists only for Android. The desktop equivalent is the
/// `sing-box` binary the distribution ships, so this controller does what the
/// VpnService does on Android — start it, watch it, report it — from the other
/// side of a process boundary:
///
///  * state comes from the process (spawn, exit code) plus a readiness probe
///    against the Clash API, since a running process is not yet a working one;
///  * logs come from the child's stdout/stderr rather than the API's log socket,
///    because the failures worth reading happen *before* anything listens;
///  * everything else — group membership, selection, URL tests, counters — goes
///    over the Clash API the rendered config already enables.
///
/// Privileges: a `tun` inbound needs `CAP_NET_ADMIN`, which Android is handed
/// after its permission dialog and Linux is not. The desktop equivalent is a
/// file capability on the engine binary, and a tun start asks for it the way the
/// rest of the desktop asks for root — a polkit prompt, put up by `pkexec`, once
/// per binary. See `linux_privileges.dart`. System-proxy mode needs nothing at
/// all, which is why it is the mode a fresh install starts in.
library;

import 'dart:async';
import 'dart:io';

import '../data/config_builder.dart';
import '../models/proxy_state.dart';
import 'app_paths.dart';
import 'clash_api.dart';
import 'config_facts.dart';
import 'core_version.dart';
import 'desktop_runtime.dart';
import 'linux_privileges.dart';
import 'linux_system_proxy.dart';
import 'proxy_controller.dart';

const _selectionConfirmTimeout = Duration(seconds: 3);

class LinuxProxyController extends DesktopRuntime implements ProxyController {
  LinuxProxyController({
    this.binaryOverride,
    LinuxSystemProxy? systemProxy,
    LinuxPrivileges? privileges,
    ClashApiClient Function({required int port, required String secret})?
        clientFactory,
    Duration readyTimeout = const Duration(seconds: 10),
    Duration groupPollInterval = const Duration(seconds: 5),
  })  : _systemProxy = systemProxy,
        _privileges = privileges ?? LinuxPrivileges(),
        _clientFactory = clientFactory ?? _defaultClient,
        _readyTimeout = readyTimeout,
        _groupPollInterval = groupPollInterval;

  /// Skips discovery. Set by tests and by `SINGBOX_BINARY`.
  final String? binaryOverride;

  final LinuxPrivileges _privileges;

  final ClashApiClient Function({required int port, required String secret})
      _clientFactory;
  final Duration _readyTimeout;
  final Duration _groupPollInterval;

  LinuxSystemProxy? _systemProxy;

  Process? _process;

  /// The binary the current or last start used: what the capability is asked for
  /// on, and what a permissions failure quotes in the `setcap` line.
  String? _binary;

  ClashApiClient? _client;
  StreamSubscription<ProxyTraffic>? _trafficSub;
  Timer? _groupPoll;

  /// Line pumps for the child's stdout and stderr, cancelled when it goes.
  final _outputSubs = <StreamSubscription<String>>[];

  /// The last lines the engine wrote. A start that fails leaves its reason
  /// here: the state message is one line, and the useful part is often the
  /// third line up.
  final _recentOutput = <String>[];
  static const _outputTail = 20;

  /// Nothing to ask for here. What a Linux tun needs is a capability on the
  /// engine binary, not a per-connection grant, and whether this start wants one
  /// is a fact about the config — so the asking happens in [start], where the
  /// rendered config says whether there is a tun at all. Reported as granted so
  /// the connect path proceeds to it.
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start(String configJson) =>
      enqueueLifecycle(() => _startInternal(configJson));

  Future<void> _startInternal(String configJson) async {
    if (isDisposed) return;
    final session = beginSession();
    if (_process != null) await _stopInternal();
    isStopping = false;
    _recentOutput.clear();
    emitState(ProxyState(stage: ProxyStage.starting, sessionId: session));

    final binary = await resolveBinary(override: binaryOverride);
    if (!isCurrentSession(session)) return;
    if (binary == null) {
      fail(EngineProblem.missing);
      return;
    }
    _binary = binary;
    final version = await readCoreVersion(binary);
    if (!isCurrentSession(session)) return;
    if (version != null && !versionAtLeast(version, singBoxMinimumVersion)) {
      fail(EngineProblem.tooOld, version.join('.'));
      return;
    }

    final settings = ConfigFacts.parse(configJson);
    if (settings.hasTun && !await _authorizeTun(binary)) return;
    if (!isCurrentSession(session)) return;

    final dataDir = await appDataDirectory();
    if (!isCurrentSession(session)) return;
    if (dataDir == null) {
      emitError('no writable data directory', session: session);
      return;
    }
    final configPath = '$dataDir${Platform.pathSeparator}config.json';
    try {
      final file = File(configPath);
      await file.writeAsString(configJson, flush: true);
      // Node credentials and the Clash API secret. Written before the engine
      // reads it, so the window where it is world-readable is not one where it
      // is also being used.
      await restrictToOwner(configPath, file: true);
    } on Object catch (error) {
      emitError(
        'could not write $configPath: $error',
        session: session,
      );
      return;
    }
    if (!isCurrentSession(session)) return;

    Process process;
    try {
      process = await Process.start(
        binary,
        // `-D` keeps the engine's own working files — cache.db, and any
        // rule-set it downloads itself — beside ours instead of in $CWD.
        // `--disable-color` is belt and braces: ProxyLogEntry strips ANSI, but
        // the diagnostic tail below is raw text.
        ['run', '-c', configPath, '-D', dataDir, '--disable-color'],
      );
    } on ProcessException catch (error) {
      emitError('$binary: ${error.message}', session: session);
      return;
    }
    if (!isCurrentSession(session)) {
      process.kill(ProcessSignal.sigterm);
      return;
    }
    _process = process;
    _outputSubs
      ..add(pipeLines(process.stdout, onLine: _engineLine))
      ..add(pipeLines(process.stderr, onLine: _engineLine));

    var exited = false;
    unawaited(process.exitCode.then((code) {
      exited = true;
      _onExit(process, code, tun: settings.hasTun, session: session);
    }));

    if (!await _awaitReady(
      settings,
      session: session,
      isDead: () => exited,
    )) {
      // _awaitReady only returns false after the failure has been reported —
      // either the process died, or it never started listening.
      return;
    }
    if (!isCurrentSession(session)) return;

    ProxyCoverage coverage;
    if (settings.wantsSystemProxy) {
      final proxy = _proxyFor(dataDir);
      await proxy.enable(host: '127.0.0.1', port: settings.mixedPort);
      if (!isCurrentSession(session)) {
        await _teardown();
        return;
      }
      for (final warning in proxy.warnings) {
        log('system proxy: $warning');
      }
      coverage = proxy.isSupported && proxy.warnings.isEmpty
          ? ProxyCoverage.systemProxy
          : ProxyCoverage.systemProxyUnavailable;
    } else if (settings.hasTun) {
      coverage = ProxyCoverage.tun;
    } else {
      coverage = ProxyCoverage.localProxy;
    }

    if (sessionId == session && !isDisposed) {
      emitState(ProxyState(
        stage: ProxyStage.connected,
        since: DateTime.now(),
        sessionId: session,
        coverage: coverage,
      ));
    }
  }

  @override
  Future<void> stop() => enqueueLifecycle(_stopInternal);

  Future<void> _stopInternal() async {
    final process = _process;
    isStopping = true;
    if (process == null) {
      await _teardown();
      isStopping = false;
      if (!isDisposed) emitState(ProxyState(sessionId: sessionId));
      return;
    }
    if (!isDisposed) {
      emitState(ProxyState(stage: ProxyStage.stopping, sessionId: sessionId));
    }
    process.kill(ProcessSignal.sigterm);
    try {
      // sing-box closes its inbounds and flushes cache.db on SIGTERM; that is
      // worth waiting for, but not forever.
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await _teardown();
    isStopping = false;
    if (!isDisposed) emitState(ProxyState(sessionId: sessionId));
  }

  @override
  Future<void> clearLogs() async {
    // Nothing to clear on this side. The supervised `sing-box` writes to
    // stdout/stderr, which is a stream rather than a buffer the engine retains,
    // and the Clash API exposes no log-clear call. AppState drops its own
    // bounded copy synchronously, which is the whole of what the user sees.
  }

  /// sing-box has no live config reload — `SIGHUP` restarts it from scratch —
  /// so this is a stop and a start, and connections do not survive it. Android
  /// reloads in place through libbox, which is why the two differ.
  @override
  Future<void> reload(String configJson) => enqueueLifecycle(() async {
        if (_process == null) throw StateError('not connected');
        await _stopInternal();
        await _startInternal(configJson);
      });

  @override
  Future<void> selectOutbound(String outboundTag) async {
    final client = _client;
    if (client == null) throw StateError('not connected');
    await client.select(ConfigTags.proxy, outboundTag);

    // A successful PUT only means the Clash API accepted the command. Wait for
    // the selector's reported `now` value before telling AppState that the
    // switch completed; otherwise the UI can show a new node while traffic is
    // still leaving through the previous one (or the API ignored an invalid
    // member for a compatible-but-different runtime).
    final deadline = DateTime.now().add(_selectionConfirmTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final group = await client.group(ConfigTags.proxy);
      if (group?.selected == outboundTag) {
        emitGroup(group!);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('sing-box did not confirm the selected node');
  }

  /// Tests every member of the selector group and reports the results.
  ///
  /// One batched request, falling back to a member at a time. The comment here
  /// used to say the Clash API had no whole-group call and that
  /// `/group/{n}/delay` was a Clash.Meta extension sing-box did not implement —
  /// which was wrong, and only this platform believed it. Windows had been
  /// calling that endpoint all along. It is served: verified against a running
  /// 1.14.0, and in `experimental/clashapi/api_meta_group.go` since 1.12, this
  /// app's minimum. See [ClashApiClient.groupDelay].
  ///
  /// Results still arrive on [groups] rather than as a return value, which is
  /// the shape Android has: there the engine pushes them.
  @override
  Future<void> urlTest() async {
    final client = _client;
    if (client == null) throw StateError('not connected');
    final group = await client.group(ConfigTags.proxy);
    if (group == null) throw StateError('no ${ConfigTags.proxy} group');

    // One request for the whole group. The engine tests the members in parallel
    // internally, which is both faster than doing it a member at a time from
    // here and one connection instead of N.
    //
    // The budget is not arbitrary: AppState waits a fixed period for readings to
    // arrive on [groups] and marks whatever has not reported unreachable. A
    // batched test reports nothing until it finishes, so its deadline has to sit
    // comfortably inside that window — otherwise a slow test would mark every
    // node unreachable instead of merely being late.
    final batched = await client.groupDelay(
      ConfigTags.proxy,
      timeout: const Duration(seconds: 6),
    );
    if (batched != null) {
      // Absent means "did not answer" — the engine omits those. The previous
      // reading is kept rather than overwritten with a zero, so one failed sweep
      // does not blank a column of latencies.
      emitGroup(ProxyGroup(
        tag: group.tag,
        selected: group.selected,
        delays: {...group.delays, ...batched},
      ));
      return;
    }

    // Fallback: one member at a time. Reached when the endpoint is not served —
    // a Clash implementation other than sing-box behind the same API — or when
    // the batched test failed outright. Slower, but it also streams its results,
    // so the UI fills in progressively.
    final members = group.delays.keys.toList();
    final results = <String, int>{...group.delays};
    const concurrency = 5;
    var index = 0;

    Future<void> worker() async {
      while (index < members.length) {
        final member = members[index++];
        // `auto` is a urltest group: asking it to test dials every member
        // again, so the group's own reading is left as it is.
        if (member == ConfigTags.auto) continue;
        results[member] = await client.delay(member);
        emitGroup(ProxyGroup(
          tag: group.tag,
          selected: group.selected,
          delays: {...results},
        ));
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < members.length; i++) worker(),
    ]);
  }

  /// `/version` while it runs, `sing-box version` otherwise — so the settings
  /// page can name the core before anything has been started.
  @override
  Future<String?> coreVersion() async {
    final running = await _client?.version();
    if (running != null && running.isNotEmpty) return _tagged(running);
    final binary = await resolveBinary(override: binaryOverride);
    if (binary == null) return null;
    final parts = await readCoreVersion(binary);
    return parts == null ? null : _tagged(parts.join('.'));
  }

  @override
  Future<void> shutdown() async {
    // Order matters. Stopping first lets sing-box close its inbounds and flush
    // its cache on SIGTERM, and the _teardown inside stop() is what puts the
    // desktop's proxy settings back — the step dispose cannot do at all.
    try {
      await enqueueLifecycle(() async {
        if (_process != null) {
          await _stopInternal();
        } else {
          // No engine of ours running, but an earlier unclean exit may still
          // have left the desktop pointed at that port. Cheap to be sure.
          await _teardown();
        }
      });
    } on Object {
      // Quitting must not hang on a stubborn engine. dispose below still sends
      // SIGTERM, and restoreSystemProxy at the next start is the backstop.
    }
    dispose();
  }

  @override
  void dispose() {
    // Disposed first, so nothing torn down below tries to emit on its way out.
    if (!markDisposed()) return;
    _groupPoll?.cancel();
    _trafficSub?.cancel();
    _client?.dispose();
    _process?.kill(ProcessSignal.sigterm);
    closeStreams();
  }

  /// Puts the desktop's proxy settings back after an unclean exit.
  ///
  /// Called once at startup: if the app was killed while connected, the desktop
  /// still points at a port with nothing behind it, and every application on it
  /// is offline until someone notices.
  Future<void> restoreSystemProxy() async {
    final dataDir = await appDataDirectory();
    if (dataDir == null) return;
    await _proxyFor(dataDir).restore();
  }

  // --- privileges -----------------------------------------------------------

  /// Makes sure [binary] can create a tun, asking the user once if it cannot.
  ///
  /// Reports the failure itself and returns false, so a caller can `return` on
  /// it. Three ways this ends without a prompt: the capability is already there
  /// (the common case, since it survives on the file), `getcap` cannot say — in
  /// which case the engine is left to try and its own error stands — or there is
  /// no way to ask, which reads the same as a refusal because the outcome is.
  Future<bool> _authorizeTun(String binary) async {
    final present = await _privileges.hasTunCapabilities(binary);
    // Null is "cannot tell": see LinuxPrivileges.hasTunCapabilities.
    if (present != false) return true;

    emitState(ProxyState(
      stage: ProxyStage.requestingPermission,
      sessionId: sessionId,
    ));
    log('tun mode: asking for $tunCapabilities on $binary');
    final outcome = await _privileges.grantTunCapabilities(binary);
    if (outcome == TunAuthorization.granted) {
      log('tun mode: $tunCapabilities granted');
      emitState(ProxyState(stage: ProxyStage.starting, sessionId: sessionId));
      return true;
    }
    // One message for every way it did not happen — dismissed, failed, or
    // nothing to ask with — because the fix the user is offered is the same:
    // authorize it, grant it by hand, or use the mode that needs neither.
    log('tun mode: not authorized (${outcome.name})');
    fail(EngineProblem.unprivileged, binary);
    return false;
  }

  // --- process plumbing -----------------------------------------------------

  /// A line the engine wrote, kept for [_tail] as well as logged.
  ///
  /// The base class's [log] is the plain path — a line from the controller
  /// itself, which reaches the log page but must stay out of [_recentOutput],
  /// since that exists to quote the *engine's* own last words back in a failure
  /// message.
  void _engineLine(String line) {
    if (line.trim().isEmpty) return;
    _recentOutput.add(line);
    if (_recentOutput.length > _outputTail) _recentOutput.removeAt(0);
    log(line);
  }

  /// Waits for the Clash API to answer, which is the first moment the engine is
  /// actually carrying traffic. Reports the failure itself and returns false.
  Future<bool> _awaitReady(
    ConfigFacts settings, {
    required int session,
    required bool Function() isDead,
  }) async {
    final client = _clientFactory(
      port: settings.clashPort,
      secret: settings.clashSecret,
    );
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isDead() || sessionId != session) {
        client.dispose();
        return false;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      if (await client.version(timeout: remaining) != null) {
        if (isDead() || sessionId != session) {
          client.dispose();
          return false;
        }
        _client = client;
        _watchTraffic(client, session: session);
        _startGroupPoll(session: session);
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    client.dispose();
    if (sessionId != session) return false;
    _process?.kill(ProcessSignal.sigterm);
    // The same condition Windows reports, so both desktops name it the same
    // way. What the engine printed while failing is not spliced in here: it is
    // already in the log stream, and a rendered config's own diagnostics can
    // carry node credentials.
    fail(EngineProblem.apiTimeout);
    return false;
  }

  void _watchTraffic(ClashApiClient client, {required int session}) {
    _trafficSub?.cancel();
    _trafficSub = client.traffic().listen(
      (value) {
        if (sessionId == session && identical(_client, client)) {
          emitTraffic(value);
        }
      },
      onError: (Object _) {},
    );
  }

  void _startGroupPoll({required int session}) {
    _groupPoll?.cancel();
    // The Clash API does not push group changes the way libbox does, so this
    // polls. Cheap — one loopback GET — and it is also how a selection made
    // elsewhere (another Clash dashboard against the same API) shows up here.
    _groupPoll = Timer.periodic(
      _groupPollInterval,
      (_) => unawaited(_pushGroup(session: session)),
    );
    unawaited(_pushGroup(session: session));
  }

  Future<void> _pushGroup({required int session}) async {
    if (sessionId != session) return;
    final client = _client;
    if (client == null) return;
    final group = await client.group(ConfigTags.proxy);
    if (group != null && sessionId == session && identical(_client, client)) {
      emitGroup(group);
    }
  }

  void _onExit(
    Process process,
    int code, {
    required bool tun,
    required int session,
  }) {
    if (_process != process || sessionId != session) {
      return; // A later start already replaced it.
    }
    _process = null;
    unawaited(_teardown());
    if (isDisposed) return;
    if (isStopping) {
      emitState(ProxyState(sessionId: session));
      return;
    }
    final tail = _tail();
    if (tun && _looksUnprivileged(tail)) {
      fail(EngineProblem.unprivileged, _binary);
      return;
    }
    emitError('sing-box exited with code $code$tail', session: session);
  }

  /// Releases everything the running engine owned. Safe to call twice.
  Future<void> _teardown() async {
    _groupPoll?.cancel();
    _groupPoll = null;
    await _trafficSub?.cancel();
    _trafficSub = null;
    // The killed process closes its pipes, and a listener left on them outlives
    // the session it belonged to.
    for (final sub in _outputSubs) {
      await sub.cancel();
    }
    _outputSubs.clear();
    _client?.dispose();
    _client = null;
    final proxy = _systemProxy;
    if (proxy != null) {
      await proxy.restore();
    } else {
      final dataDir = await appDataDirectory();
      if (dataDir != null) await _proxyFor(dataDir).restore();
    }
  }

  LinuxSystemProxy _proxyFor(String dataDir) =>
      _systemProxy ??= LinuxSystemProxy(stateDirectory: dataDir);

  /// The engine's last words, for an error message. Empty when it said nothing.
  String _tail() =>
      _recentOutput.isEmpty ? '' : ': ${_recentOutput.join(' | ')}';

  /// Whether a failed tun start was a permissions problem.
  ///
  /// The engine's wording is not ours and could change, so this is a hint that
  /// picks a better message — never a gate on anything.
  static bool _looksUnprivileged(String output) {
    final text = output.toLowerCase();
    return text.contains('operation not permitted') ||
        text.contains('permission denied') ||
        text.contains('/dev/net/tun') ||
        text.contains('cap_net_admin');
  }

  static String _tagged(String version) =>
      version.startsWith('v') ? version : 'v$version';

  // --- discovery ------------------------------------------------------------

  /// Where the `sing-box` binary is, or null.
  ///
  /// In order: an explicit override or `SINGBOX_BINARY`, a copy installed
  /// beside the app under `/usr/lib/singbox-client`, then `PATH`. The middle
  /// one is a hook for a future package that ships its own engine; nothing
  /// installs there today.
  static Future<String?> resolveBinary({String? override}) async {
    final explicit = override ?? Platform.environment['SINGBOX_BINARY'];
    if (explicit != null && explicit.isNotEmpty) {
      return File(explicit).existsSync() ? explicit : null;
    }
    const bundled = '/usr/lib/singbox-client/sing-box';
    if (File(bundled).existsSync()) return bundled;
    for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
      if (dir.isEmpty) continue;
      final candidate = '$dir/sing-box';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static ClashApiClient _defaultClient({
    required int port,
    required String secret,
  }) =>
      ClashApiClient(port: port, secret: secret);
}
