/// Points the desktop's proxy settings at the local `mixed` inbound.
///
/// System-proxy mode needs no privileges, and this is what it costs instead:
/// there is no single place on Linux to say "everything goes through here".
/// Each desktop keeps its own answer — GNOME in GSettings, KDE in `kioslaverc`
/// — and applications that read neither are simply not covered. Nothing here
/// can reach a process that is already running, either: `http_proxy` is copied
/// into a process's environment at exec time, so an open terminal or browser
/// keeps whatever it started with.
///
/// The previous values are written to disk before anything is changed, so a
/// crash or a `kill -9` does not leave the desktop pointed at a proxy that is
/// no longer listening: the next launch finds the file and restores from it.
library;

import 'dart:convert';
import 'dart:io';

/// Runs a command and reports how it went. Injectable so the argv can be tested
/// without touching the desktop's real settings.
typedef CommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Which desktop's settings are being written.
enum SystemProxyBackend {
  /// GSettings — GNOME and the desktops that follow its schema.
  gnome,

  /// `kioslaverc`, via `kwriteconfig6` or `kwriteconfig5`.
  kde,

  /// Nothing recognised. The proxy still listens; nothing is told about it.
  unsupported;

  /// Reads `XDG_CURRENT_DESKTOP`, which is a colon-separated list.
  ///
  /// Cinnamon, MATE, Budgie and Unity all honour the GNOME schema, so they map
  /// to [gnome] rather than to nothing.
  static SystemProxyBackend detect([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final desktops =
        (env['XDG_CURRENT_DESKTOP'] ?? env['DESKTOP_SESSION'] ?? '')
            .toLowerCase()
            .split(':')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty);
    for (final desktop in desktops) {
      if (desktop.contains('kde') || desktop.contains('plasma')) {
        return SystemProxyBackend.kde;
      }
      if (desktop.contains('gnome') ||
          desktop.contains('unity') ||
          desktop.contains('cinnamon') ||
          desktop.contains('mate') ||
          desktop.contains('budgie') ||
          desktop.contains('pantheon')) {
        return SystemProxyBackend.gnome;
      }
    }
    return SystemProxyBackend.unsupported;
  }
}

/// The GSettings keys this touches, as (schema, key) pairs.
///
/// `ignore-hosts` is deliberately absent: it is the user's own bypass list, and
/// the rendered config already sends private ranges direct.
const _gnomeKeys = <(String, String)>[
  ('org.gnome.system.proxy', 'mode'),
  ('org.gnome.system.proxy.http', 'host'),
  ('org.gnome.system.proxy.http', 'port'),
  ('org.gnome.system.proxy.https', 'host'),
  ('org.gnome.system.proxy.https', 'port'),
  ('org.gnome.system.proxy.socks', 'host'),
  ('org.gnome.system.proxy.socks', 'port'),
];

/// The `kioslaverc` keys, all under one group.
const _kdeGroup = 'Proxy Settings';
const _kdeKeys = <String>['ProxyType', 'httpProxy', 'httpsProxy', 'socksProxy'];

class LinuxSystemProxy {
  LinuxSystemProxy({
    required this.stateDirectory,
    CommandRunner? runner,
    SystemProxyBackend? backend,
    Map<String, String>? environment,
  })  : _run = runner ?? _runProcess,
        backend = backend ?? SystemProxyBackend.detect(environment);

  /// Where the previous values are parked. Null disables the backup, which is
  /// what tests without a temp directory want.
  final String? stateDirectory;

  final SystemProxyBackend backend;
  final CommandRunner _run;

  static const _stateFile = 'system-proxy.backup.json';

  /// Everything this could not do, in the order it happened. The controller
  /// forwards these into the log page: a best-effort backend that silently does
  /// nothing is indistinguishable from a broken proxy.
  final warnings = <String>[];

  bool get isSupported => backend != SystemProxyBackend.unsupported;

  /// Sends HTTP, HTTPS and SOCKS traffic to [host]:[port].
  ///
  /// Saves the current values first — and only on the first enable, so a second
  /// call cannot overwrite the backup with this proxy's own settings.
  Future<void> enable({required String host, required int port}) async {
    warnings.clear();
    if (!isSupported) {
      warnings.add(
        'no system proxy backend for this desktop; point applications at '
        'http://$host:$port yourself',
      );
      return;
    }

    final backup = await _readBackup();
    if (backup == null && stateDirectory != null) {
      final snapshot = await _snapshot();
      if (warnings.isNotEmpty) {
        warnings
            .add('system proxy was not changed because its snapshot failed');
        return;
      }
      if (!await _writeBackup(snapshot)) return;
    }

    var failed = false;
    for (final command in enableCommands(host: host, port: port)) {
      final result = await _exec(command);
      if (result?.exitCode != 0 || result == null) failed = true;
    }
    if (!failed || stateDirectory == null) return;

    // Some desktop backends apply settings one command at a time. If a later
    // command fails, restore the complete snapshot instead of leaving a mixed
    // set of the user's values and ours. Keep the original failure visible in
    // the log; restore() clears its own transient warning list while working.
    final applyWarnings = [...warnings];
    await restore();
    warnings.insertAll(0, applyWarnings);
    if (warnings.isEmpty) {
      warnings.add('system proxy update failed and was rolled back');
    }
  }

  /// Puts back whatever was there before, and forgets the backup.
  ///
  /// Called on stop and again at startup, because the second case is the one
  /// that matters: if the app was killed while connected, the desktop is still
  /// pointed at a port with nothing behind it.
  Future<void> restore() async {
    warnings.clear();
    final backup = await _readBackup();
    if (backup == null) return;
    var failed = false;
    for (final command in restoreCommands(backup)) {
      final result = await _exec(command);
      if (result?.exitCode != 0 || result == null) failed = true;
    }
    if (failed) {
      warnings.add(
        'system proxy could not be fully restored; retrying on next launch',
      );
      return;
    }
    await _clearBackup();
  }

  /// The argv to apply the proxy. Pure, so tests can assert on it.
  List<List<String>> enableCommands({
    required String host,
    required int port,
  }) =>
      switch (backend) {
        SystemProxyBackend.gnome => [
            _gsettingsSet('org.gnome.system.proxy', 'mode', 'manual'),
            for (final schema in ['http', 'https', 'socks']) ...[
              _gsettingsSet('org.gnome.system.proxy.$schema', 'host', host),
              _gsettingsSet('org.gnome.system.proxy.$schema', 'port', '$port'),
            ],
          ],
        SystemProxyBackend.kde => [
            // 1 is "use manually specified settings". KDE stores the address
            // and port in one value, separated by a space.
            _kwriteconfig('ProxyType', '1'),
            _kwriteconfig('httpProxy', 'http://$host $port'),
            _kwriteconfig('httpsProxy', 'http://$host $port'),
            _kwriteconfig('socksProxy', 'socks://$host $port'),
          ],
        SystemProxyBackend.unsupported => const [],
      };

  /// The argv to put [backup]'s values back.
  List<List<String>> restoreCommands(Map<String, String> backup) =>
      switch (backend) {
        SystemProxyBackend.gnome => [
            for (final (schema, key) in _gnomeKeys)
              if (backup['$schema/$key'] case final value?)
                _gsettingsSet(schema, key, value, raw: true),
          ],
        SystemProxyBackend.kde => [
            for (final key in _kdeKeys)
              if (backup[key] case final value?)
                if (value.isEmpty)
                  // An absent key is not the same as an empty one: writing ''
                  // would leave a stale entry behind.
                  _kwriteconfig(key, null)
                else
                  _kwriteconfig(key, value),
          ],
        SystemProxyBackend.unsupported => const [],
      };

  List<String> _gsettingsSet(
    String schema,
    String key,
    String value, {
    bool raw = false,
  }) =>
      [
        'gsettings',
        'set',
        schema,
        key,
        // A saved value comes back from `gsettings get` already in GVariant
        // form — `'manual'`, quotes included — and goes back verbatim. A value
        // of ours is a bare string and gets its own quotes, except for ports,
        // which are integers in the schema and must not be quoted.
        if (raw || int.tryParse(value) != null) value else "'$value'",
      ];

  List<String> _kwriteconfig(String key, String? value) => [
        _kdeWriter,
        '--file',
        'kioslaverc',
        '--group',
        _kdeGroup,
        '--key',
        key,
        if (value == null) '--delete' else value,
      ];

  /// `kwriteconfig6` on Plasma 6, `kwriteconfig5` before it. Resolved once and
  /// cached: the fallback costs a failed exec, and it never changes mid-run.
  String get _kdeWriter => _kdeWriterCache ??= _findKdeWriter();
  String? _kdeWriterCache;

  static String _findKdeWriter() {
    for (final candidate in ['kwriteconfig6', 'kwriteconfig5']) {
      for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
        if (dir.isEmpty) continue;
        if (File('$dir/$candidate').existsSync()) return candidate;
      }
    }
    return 'kwriteconfig6';
  }

  /// Current values, as the restore map. Keys are backend-shaped: `schema/key`
  /// for GSettings, the bare key name for KDE.
  Future<Map<String, String>> _snapshot() async {
    final values = <String, String>{};
    switch (backend) {
      case SystemProxyBackend.gnome:
        for (final (schema, key) in _gnomeKeys) {
          final result = await _exec(['gsettings', 'get', schema, key]);
          if (result?.exitCode != 0) continue;
          values['$schema/$key'] = '${result!.stdout}'.trim();
        }
      case SystemProxyBackend.kde:
        for (final key in _kdeKeys) {
          final reader = _kdeWriter.replaceFirst('kwrite', 'kread');
          final result = await _exec([
            reader,
            '--file',
            'kioslaverc',
            '--group',
            _kdeGroup,
            '--key',
            key,
          ]);
          if (result?.exitCode != 0) continue;
          values[key] = '${result!.stdout}'.trim();
        }
      case SystemProxyBackend.unsupported:
        break;
    }
    return values;
  }

  Future<ProcessResult?> _exec(List<String> command) async {
    try {
      final result = await _run(command.first, command.sublist(1));
      if (result.exitCode != 0) {
        warnings.add(
          '${command.first} failed (${result.exitCode}): '
          '${'${result.stderr}'.trim()}',
        );
      }
      return result;
    } on ProcessException catch (error) {
      warnings.add('${command.first} not available: ${error.message}');
      return null;
    }
  }

  File? get _backupFile => stateDirectory == null
      ? null
      : File('$stateDirectory${Platform.pathSeparator}$_stateFile');

  Future<Map<String, String>?> _readBackup() async {
    final file = _backupFile;
    if (file == null || !file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      // A backup from another desktop cannot be replayed here.
      if (decoded['backend'] != backend.name) return null;
      final values = decoded['values'];
      if (values is! Map) return null;
      return {
        for (final entry in values.entries)
          entry.key.toString(): '${entry.value}',
      };
    } on Object {
      return null;
    }
  }

  Future<bool> _writeBackup(Map<String, String> values) async {
    final file = _backupFile;
    if (file == null) return true;
    final temporary = File('${file.path}.tmp-$pid');
    try {
      await temporary.writeAsString(
        jsonEncode({'backend': backend.name, 'values': values}),
        flush: true,
      );
      await temporary.rename(file.path);
      return true;
    } on Object {
      warnings.add('could not save the previous proxy settings');
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Object {
        // A failed temporary cleanup is harmless; the next write uses a new
        // per-process name.
      }
      return false;
    }
  }

  Future<bool> _clearBackup() async {
    try {
      final file = _backupFile;
      if (file != null && file.existsSync()) await file.delete();
      return true;
    } on Object {
      warnings.add(
        'could not clear the saved proxy settings; retrying on next launch',
      );
      return false;
    }
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) =>
      Process.run(executable, arguments);
}
