/// The desktop proxy settings, against a fake command runner.
///
/// Every one of these writes touches the user's own desktop, so the argv is the
/// contract: a quoted port, a `--delete` that arrives as an empty string, or a
/// GNOME backup replayed onto KDE all fail silently at runtime and leave the
/// desktop pointed somewhere it should not be. Asserting the argv is the only
/// way to see it without a session to break.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/platform/linux_system_proxy.dart';

/// Records what was run, and answers however the test needs it to.
class _Runner {
  final calls = <List<String>>[];

  /// Stdout per argv — how `gsettings get` and `kreadconfig` report the values
  /// that end up in the backup.
  String Function(List<String> argv) stdout = (_) => '';
  int Function(List<String> argv) exitCode = (_) => 0;
  String Function(List<String> argv) stderr = (_) => '';

  /// Executables that are not installed. These throw, as `Process.run` does.
  Set<String> missing = {};

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    final argv = [executable, ...arguments];
    calls.add(argv);
    if (missing.contains(executable)) {
      throw ProcessException(executable, arguments, 'No such file', 2);
    }
    return ProcessResult(1, exitCode(argv), stdout(argv), stderr(argv));
  }

  /// The calls that write, dropping the `get` half of a first-enable snapshot.
  List<List<String>> get writes => calls
      .where((argv) => argv[1] != 'get' && !argv.first.startsWith('kread'))
      .toList();
}

void main() {
  late _Runner runner;

  setUp(() => runner = _Runner());

  String tempDir() {
    final dir = Directory.systemTemp.createTempSync('singbox_proxy_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir.path;
  }

  LinuxSystemProxy proxy({
    SystemProxyBackend backend = SystemProxyBackend.gnome,
    String? stateDirectory,
  }) =>
      LinuxSystemProxy(
        stateDirectory: stateDirectory,
        runner: runner.call,
        backend: backend,
      );

  File backupFile(String dir) => File('$dir/system-proxy.backup.json');

  group('backend detection', () {
    test('reads XDG_CURRENT_DESKTOP', () {
      expect(
        SystemProxyBackend.detect(const {'XDG_CURRENT_DESKTOP': 'GNOME'}),
        SystemProxyBackend.gnome,
      );
      expect(
        SystemProxyBackend.detect(const {'XDG_CURRENT_DESKTOP': 'KDE'}),
        SystemProxyBackend.kde,
      );
    });

    test('plasma counts as KDE', () {
      expect(
        SystemProxyBackend.detect(
            const {'XDG_CURRENT_DESKTOP': 'plasmawayland'}),
        SystemProxyBackend.kde,
      );
    });

    test('splits the colon-separated list', () {
      expect(
        SystemProxyBackend.detect(
            const {'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME'}),
        SystemProxyBackend.gnome,
      );
    });

    test('the first recognised entry wins', () {
      expect(
        SystemProxyBackend.detect(const {'XDG_CURRENT_DESKTOP': 'KDE:GNOME'}),
        SystemProxyBackend.kde,
      );
      expect(
        SystemProxyBackend.detect(const {'XDG_CURRENT_DESKTOP': 'GNOME:KDE'}),
        SystemProxyBackend.gnome,
      );
    });

    test('the GNOME-schema desktops map to gnome, not to nothing', () {
      for (final desktop in [
        'X-Cinnamon',
        'MATE',
        'Budgie:GNOME',
        'Unity',
        'Pantheon'
      ]) {
        expect(
          SystemProxyBackend.detect({'XDG_CURRENT_DESKTOP': desktop}),
          SystemProxyBackend.gnome,
          reason: '$desktop honours the GNOME schema',
        );
      }
    });

    test('falls back to DESKTOP_SESSION', () {
      expect(
        SystemProxyBackend.detect(const {'DESKTOP_SESSION': 'plasma'}),
        SystemProxyBackend.kde,
      );
    });

    test('an unknown or absent desktop is unsupported', () {
      expect(
        SystemProxyBackend.detect(const {'XDG_CURRENT_DESKTOP': 'sway'}),
        SystemProxyBackend.unsupported,
      );
      expect(
          SystemProxyBackend.detect(const {}), SystemProxyBackend.unsupported);
      expect(
        SystemProxyBackend.detect(const {'XDG_CURRENT_DESKTOP': ''}),
        SystemProxyBackend.unsupported,
      );
    });
  });

  group('gnome', () {
    test('enable sets the mode and all three schemas', () {
      final commands = proxy().enableCommands(host: '127.0.0.1', port: 2080);
      expect(commands, [
        ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', "'manual'"],
        [
          'gsettings',
          'set',
          'org.gnome.system.proxy.http',
          'host',
          "'127.0.0.1'"
        ],
        ['gsettings', 'set', 'org.gnome.system.proxy.http', 'port', '2080'],
        [
          'gsettings',
          'set',
          'org.gnome.system.proxy.https',
          'host',
          "'127.0.0.1'"
        ],
        ['gsettings', 'set', 'org.gnome.system.proxy.https', 'port', '2080'],
        [
          'gsettings',
          'set',
          'org.gnome.system.proxy.socks',
          'host',
          "'127.0.0.1'"
        ],
        ['gsettings', 'set', 'org.gnome.system.proxy.socks', 'port', '2080'],
      ]);
    });

    test('the port goes in bare and the host quoted', () {
      final commands = proxy().enableCommands(host: 'localhost', port: 1080);
      final ports = commands.where((argv) => argv[3] == 'port');
      final hosts = commands.where((argv) => argv[3] == 'host');
      expect(ports.map((argv) => argv.last), everyElement('1080'),
          reason: 'the schema types the port as an integer');
      expect(hosts.map((argv) => argv.last), everyElement("'localhost'"),
          reason: 'a string needs its own GVariant quotes');
    });

    test('restore replays the saved values verbatim', () {
      final commands = proxy().restoreCommands(const {
        'org.gnome.system.proxy/mode': "'none'",
        'org.gnome.system.proxy.http/host': "''",
        'org.gnome.system.proxy.http/port': '0',
      });
      expect(commands, [
        ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', "'none'"],
        ['gsettings', 'set', 'org.gnome.system.proxy.http', 'host', "''"],
        ['gsettings', 'set', 'org.gnome.system.proxy.http', 'port', '0'],
      ]);
    });

    test('restore skips keys the backup does not carry', () {
      final commands = proxy().restoreCommands(const {
        'org.gnome.system.proxy/mode': "'auto'",
      });
      expect(commands, hasLength(1));
      expect(commands.single.last, "'auto'");
    });
  });

  group('kde', () {
    /// Whichever writer is on this machine's PATH; the fallback is 6.
    Matcher isKdeWriter() => matches(RegExp(r'^kwriteconfig[56]$'));

    test('enable writes the manual mode and the space-separated addresses', () {
      final commands = proxy(backend: SystemProxyBackend.kde)
          .enableCommands(host: '127.0.0.1', port: 2080);
      expect(commands, hasLength(4));
      for (final argv in commands) {
        expect(argv.first, isKdeWriter());
        expect(argv.sublist(1, 6),
            ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key']);
      }
      expect(
        commands.map((argv) => argv.sublist(6)),
        [
          ['ProxyType', '1'],
          ['httpProxy', 'http://127.0.0.1 2080'],
          ['httpsProxy', 'http://127.0.0.1 2080'],
          ['socksProxy', 'socks://127.0.0.1 2080'],
        ],
        reason: 'KDE keeps the address and port in one value, space separated',
      );
    });

    test('restore puts back what was saved', () {
      final commands = proxy(backend: SystemProxyBackend.kde).restoreCommands(
        const {'ProxyType': '0', 'httpProxy': 'http://cache.example 8080'},
      );
      expect(
        commands.map((argv) => argv.sublist(6)),
        [
          ['ProxyType', '0'],
          ['httpProxy', 'http://cache.example 8080'],
        ],
      );
    });

    test('an empty saved value restores as a delete, not as an empty write',
        () {
      final commands = proxy(backend: SystemProxyBackend.kde)
          .restoreCommands(const {'httpProxy': ''});
      expect(commands.single.sublist(6), ['httpProxy', '--delete'],
          reason: 'writing an empty string would leave a stale entry behind');
    });
  });

  group('unsupported', () {
    test('produces no commands', () {
      final subject = proxy(backend: SystemProxyBackend.unsupported);
      expect(subject.isSupported, isFalse);
      expect(subject.enableCommands(host: '127.0.0.1', port: 2080), isEmpty);
      expect(subject.restoreCommands(const {'ProxyType': '1'}), isEmpty);
    });

    test('enable runs nothing and says where to point applications', () async {
      final subject = proxy(backend: SystemProxyBackend.unsupported);
      await subject.enable(host: '127.0.0.1', port: 2080);
      expect(runner.calls, isEmpty);
      expect(subject.warnings.single, contains('http://127.0.0.1:2080'));
    });

    test('no backup is written, so restore has nothing to replay', () async {
      final dir = tempDir();
      final subject =
          proxy(backend: SystemProxyBackend.unsupported, stateDirectory: dir);
      await subject.enable(host: '127.0.0.1', port: 2080);
      expect(backupFile(dir).existsSync(), isFalse);
    });
  });

  group('backup', () {
    test('the first enable snapshots the current values', () async {
      final dir = tempDir();
      runner.stdout = (argv) => argv[1] == 'get' ? "'none'" : '';
      await proxy(stateDirectory: dir).enable(host: '127.0.0.1', port: 2080);

      final decoded = jsonDecode(backupFile(dir).readAsStringSync())
          as Map<String, Object?>;
      expect(decoded['backend'], 'gnome');
      expect(decoded['values'], {
        'org.gnome.system.proxy/mode': "'none'",
        'org.gnome.system.proxy.http/host': "'none'",
        'org.gnome.system.proxy.http/port': "'none'",
        'org.gnome.system.proxy.https/host': "'none'",
        'org.gnome.system.proxy.https/port': "'none'",
        'org.gnome.system.proxy.socks/host': "'none'",
        'org.gnome.system.proxy.socks/port': "'none'",
      });
    });

    test('a second enable does not overwrite it with our own settings',
        () async {
      final dir = tempDir();
      runner.stdout = (argv) => argv[1] == 'get' ? "'none'" : '';
      final subject = proxy(stateDirectory: dir);
      await subject.enable(host: '127.0.0.1', port: 2080);
      final first = backupFile(dir).readAsStringSync();

      runner.stdout = (argv) => argv[1] == 'get' ? "'manual'" : '';
      await subject.enable(host: '127.0.0.1', port: 2080);

      expect(backupFile(dir).readAsStringSync(), first);
      expect(runner.calls.where((argv) => argv[1] == 'get'), hasLength(7),
          reason: 'the second enable must not snapshot at all');
    });

    test('a partial snapshot prevents an unsafe proxy update', () async {
      final dir = tempDir();
      runner.exitCode =
          (argv) => argv[1] == 'get' && argv[2].endsWith('.socks') ? 1 : 0;
      runner.stdout = (argv) => argv[1] == 'get' ? "'none'" : '';
      final subject = proxy(stateDirectory: dir);
      await subject.enable(host: '127.0.0.1', port: 2080);

      expect(backupFile(dir).existsSync(), isFalse,
          reason: 'an incomplete snapshot must not become a restore journal');
      expect(
        subject.warnings.any((warning) => warning.contains('snapshot failed')),
        isTrue,
      );
      expect(runner.writes, isEmpty,
          reason: 'the desktop must remain untouched when its snapshot fails');
    });

    test('restore replays the file and then forgets it', () async {
      final dir = tempDir();
      backupFile(dir).writeAsStringSync(jsonEncode({
        'backend': 'gnome',
        'values': {'org.gnome.system.proxy/mode': "'none'"},
      }));

      final subject = proxy(stateDirectory: dir);
      await subject.restore();

      expect(runner.writes.single,
          ['gsettings', 'set', 'org.gnome.system.proxy', 'mode', "'none'"]);
      expect(backupFile(dir).existsSync(), isFalse);
    });

    test('a backup from another desktop is not replayed', () async {
      final dir = tempDir();
      backupFile(dir).writeAsStringSync(jsonEncode({
        'backend': 'kde',
        'values': {'ProxyType': '0'},
      }));

      await proxy(stateDirectory: dir).restore();

      expect(runner.calls, isEmpty,
          reason: 'KDE keys mean nothing to gsettings');
    });

    test('a mismatched backup does not block a fresh snapshot', () async {
      final dir = tempDir();
      backupFile(dir).writeAsStringSync(jsonEncode({
        'backend': 'kde',
        'values': {'ProxyType': '0'},
      }));
      runner.stdout = (argv) => argv[1] == 'get' ? "'auto'" : '';

      await proxy(stateDirectory: dir).enable(host: '127.0.0.1', port: 2080);

      final decoded = jsonDecode(backupFile(dir).readAsStringSync())
          as Map<String, Object?>;
      expect(decoded['backend'], 'gnome');
    });

    test('a corrupt backup is ignored', () async {
      final dir = tempDir();
      backupFile(dir).writeAsStringSync('{not json');
      await proxy(stateDirectory: dir).restore();
      expect(runner.calls, isEmpty);
    });

    test('restore without a backup runs nothing', () async {
      await proxy(stateDirectory: tempDir()).restore();
      expect(runner.calls, isEmpty);
    });

    test('no state directory still applies the proxy', () async {
      final subject = proxy();
      await subject.enable(host: '127.0.0.1', port: 2080);
      expect(runner.writes, hasLength(7));
      expect(subject.warnings, isEmpty,
          reason: 'a disabled backup is a choice, not a failure');
    });
  });

  group('warnings', () {
    test('a failed write is reported with its exit code and stderr', () async {
      runner.exitCode = (argv) => argv.last == "'manual'" ? 2 : 0;
      runner.stderr = (_) => 'No such schema\n';

      final subject = proxy();
      await subject.enable(host: '127.0.0.1', port: 2080);

      expect(
          subject.warnings.single,
          allOf(
            contains('gsettings'),
            contains('2'),
            contains('No such schema'),
          ));
    });

    test('a missing executable is reported rather than thrown', () async {
      runner.missing = {'gsettings'};
      final subject = proxy();
      await subject.enable(host: '127.0.0.1', port: 2080);
      // A disabled backup means there is no reason to read a snapshot first;
      // each attempted write still reports the missing executable.
      expect(subject.warnings, hasLength(7));
      expect(subject.warnings.first, contains('not available'));
    });

    test('each call starts from a clean list', () async {
      runner.exitCode = (_) => 1;
      final subject = proxy();
      await subject.enable(host: '127.0.0.1', port: 2080);
      expect(subject.warnings, hasLength(7));

      runner.exitCode = (_) => 0;
      await subject.enable(host: '127.0.0.1', port: 2080);
      expect(subject.warnings, isEmpty);
    });

    test('rolls back a partially applied proxy update', () async {
      final dir = tempDir();
      var failOnce = true;
      runner.exitCode = (argv) {
        if (failOnce && argv[1] == 'set' && argv[3] == 'port') {
          failOnce = false;
          return 2;
        }
        return 0;
      };
      runner.stdout = (argv) => argv[1] == 'get' ? "'none'" : '';

      final subject = proxy(stateDirectory: dir);
      await subject.enable(host: '127.0.0.1', port: 2080);

      expect(subject.warnings, hasLength(1));
      expect(backupFile(dir).existsSync(), isFalse,
          reason: 'a successful rollback can remove its journal');
      expect(
        runner.writes.any((argv) =>
            argv.length == 5 &&
            argv[0] == 'gsettings' &&
            argv[1] == 'set' &&
            argv[2] == 'org.gnome.system.proxy' &&
            argv[3] == 'mode' &&
            argv[4] == "'none'"),
        isTrue,
        reason: 'the old mode was replayed after a later write failed',
      );
    });

    test('keeps the journal when restoring the desktop fails', () async {
      final dir = tempDir();
      runner.stdout = (argv) => argv[1] == 'get' ? "'none'" : '';
      final subject = proxy(stateDirectory: dir);
      await subject.enable(host: '127.0.0.1', port: 2080);
      expect(backupFile(dir).existsSync(), isTrue);

      runner.exitCode = (argv) => argv.last == "'none'" ? 2 : 0;
      await subject.restore();

      expect(subject.warnings, isNotEmpty);
      expect(backupFile(dir).existsSync(), isTrue,
          reason: 'a later launch needs the snapshot to retry restoration');
    });
  });
}
