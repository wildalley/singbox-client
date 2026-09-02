/// The tun capability grant, against a fake command runner.
///
/// This is the one place in the app that asks for root, so the argv is the
/// contract: what gets elevated, and what does not. `setcap` run as root against
/// a path this picked up from the environment would turn `SINGBOX_BINARY` into a
/// capability grant on a file of someone else's choosing, and the only way to see
/// that here is to assert the command rather than run it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/platform/linux_privileges.dart';

/// Records what was run, and answers however the test needs it to.
class _Runner {
  final calls = <List<String>>[];

  String Function(List<String> argv) stdout = (_) => '';
  int Function(List<String> argv) exitCode = (_) => 0;

  /// Tools that are not installed. Consulted both by the lookup and — for the
  /// ones that get as far as running — by the call itself, as `Process.run` does.
  Set<String> missing = {};

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    final argv = [executable, ...arguments];
    calls.add(argv);
    if (missing.contains(executable)) {
      throw ProcessException(executable, arguments, 'No such file', 2);
    }
    return ProcessResult(1, exitCode(argv), stdout(argv), '');
  }
}

void main() {
  late _Runner runner;

  setUp(() => runner = _Runner());

  /// A binary path the trust check accepts, without needing one to exist.
  const trusted = '/usr/bin/sing-box';

  /// The tools resolve out of the first search path, and their presence is
  /// answered from [_Runner.missing] rather than from this host: CI containers
  /// ship no `pkexec`, and the argv is the thing under test either way.
  LinuxPrivileges privileges({Iterable<String>? trustedRoots}) =>
      LinuxPrivileges(
        runner: runner.call,
        trustedRoots: trustedRoots,
        exists: (path) => !runner.missing.contains(path),
      );

  group('reading the capabilities', () {
    test('the libcap 2.60 format counts as granted', () {
      expect(
        LinuxPrivileges.capabilitiesPresent(
          '/usr/bin/sing-box cap_net_admin,cap_net_raw=ep\n',
        ),
        isTrue,
      );
    });

    test('the older format counts as granted', () {
      expect(
        LinuxPrivileges.capabilitiesPresent(
          '/usr/bin/sing-box = cap_net_admin,cap_net_raw+ep\n',
        ),
        isTrue,
      );
    });

    test('no output at all is an unprivileged binary', () {
      expect(LinuxPrivileges.capabilitiesPresent(''), isFalse);
    });

    test('half the set is not the set', () {
      // A tun needs both. Reading this as granted would skip the prompt and let
      // the engine fail on its own, which is the failure the prompt replaces.
      expect(
        LinuxPrivileges.capabilitiesPresent('/usr/bin/sing-box cap_net_admin=ep'),
        isFalse,
      );
    });

    test('permitted but not effective is not granted', () {
      // sing-box does not raise its own capabilities, so `=p` leaves it unable
      // to use them.
      expect(
        LinuxPrivileges.capabilitiesPresent(
          '/usr/bin/sing-box cap_net_admin,cap_net_raw=p',
        ),
        isFalse,
      );
    });

    test('a path that happens to contain the flag letters is not the flag', () {
      // "/opt/step/" carries an "ep" of its own. Reading the whole line for that
      // substring would call a permitted-only binary effective.
      expect(
        LinuxPrivileges.capabilitiesPresent(
          '/opt/step/sing-box cap_net_admin,cap_net_raw=p',
        ),
        isFalse,
      );
    });

    test('a binary with the capabilities needs no prompt', () async {
      runner.stdout = (_) => '$trusted cap_net_admin,cap_net_raw=ep\n';
      expect(await privileges().hasTunCapabilities(trusted), isTrue);
    });

    test('a binary without them reports false', () async {
      expect(await privileges().hasTunCapabilities(trusted), isFalse);
    });

    test('an unreadable answer is null, not false', () async {
      // Null means "cannot tell", and the controller starts the engine anyway
      // rather than putting up a prompt that cannot help.
      runner.exitCode = (_) => 1;
      expect(await privileges().hasTunCapabilities(trusted), isNull);

      runner.exitCode = (_) => 0;
      runner.missing = {'/usr/sbin/getcap', '/usr/bin/getcap', '/sbin/getcap',
        '/bin/getcap'};
      expect(await privileges().hasTunCapabilities(trusted), isNull);
    });
  });

  group('what may be elevated', () {
    test('a system-installed sing-box may', () {
      final subject = privileges();
      for (final path in [
        '/usr/bin/sing-box',
        '/usr/local/bin/sing-box',
        '/usr/lib/singbox-client/sing-box',
        '/opt/sing-box/sing-box',
      ]) {
        expect(subject.mayElevate(path), isTrue, reason: path);
      }
    });

    test('a path outside the system locations may not', () {
      // Where SINGBOX_BINARY points during development. It still runs; it just
      // has to be granted by hand rather than by a root command this builds.
      final subject = privileges();
      for (final path in [
        '/home/dev/sing-box',
        '/tmp/sing-box',
        'sing-box',
        './sing-box',
        '/usr/bin/../../tmp/sing-box',
      ]) {
        expect(subject.mayElevate(path), isFalse, reason: path);
      }
    });

    test('only a binary named sing-box may', () {
      // The name is the second half of the check: a trusted directory full of
      // other people's binaries is not a licence to grant any of them.
      expect(privileges().mayElevate('/usr/bin/bash'), isFalse);
      expect(privileges().mayElevate('/usr/bin/sing-box-wrapper'), isFalse);
    });

    test('an untrusted path is refused without running anything', () async {
      final outcome =
          await privileges().grantTunCapabilities('/tmp/sing-box');

      expect(outcome, TunAuthorization.unavailable);
      expect(runner.calls, isEmpty,
          reason: 'nothing may reach pkexec before the path is vetted');
    });
  });

  group('the grant', () {
    test('is pkexec, setcap, the capability set, and the binary', () async {
      await privileges().grantTunCapabilities(trusted);

      expect(runner.calls, hasLength(1));
      final argv = runner.calls.single;
      expect(argv[0], endsWith('/pkexec'),
          reason: 'polkit is what puts the dialog up');
      expect(argv[1], endsWith('/setcap'));
      expect(argv[2], 'cap_net_admin,cap_net_raw+ep');
      expect(argv[3], trusted);
      expect(argv, hasLength(4),
          reason: 'no shell, no extra words: the path is one argument');
    });

    test('the tools are absolute paths, not names to look up', () async {
      // pkexec runs its argument as root. Resolving that through PATH is how a
      // PATH-injection bug gets written.
      await privileges().grantTunCapabilities(trusted);
      for (final argument in runner.calls.single.take(2)) {
        expect(argument, startsWith('/'));
      }
    });

    test('exit 0 is granted', () async {
      expect(
        await privileges().grantTunCapabilities(trusted),
        TunAuthorization.granted,
      );
    });

    test('a dismissed dialog and a failed authentication are declined', () {
      // 126 and 127 are pkexec's own codes for "the user did not authorize
      // this". The user's answer, so nothing retries on its own.
      expect(LinuxPrivileges.outcomeOf(126), TunAuthorization.declined);
      expect(LinuxPrivileges.outcomeOf(127), TunAuthorization.declined);
    });

    test('any other non-zero code is a failure', () {
      expect(LinuxPrivileges.outcomeOf(1), TunAuthorization.failed);
      expect(LinuxPrivileges.outcomeOf(2), TunAuthorization.failed);
    });

    test('a missing pkexec is reported rather than thrown', () async {
      runner.missing = {'/usr/bin/pkexec', '/usr/sbin/pkexec', '/bin/pkexec',
        '/sbin/pkexec'};

      expect(
        await privileges().grantTunCapabilities(trusted),
        TunAuthorization.unavailable,
      );
    });

    test('the trusted roots are what the check consults', () async {
      // The knob a distribution needs if it installs the engine somewhere else,
      // and the reason this suite can assert on paths that do not exist here.
      final subject = privileges(trustedRoots: const ['/srv/']);

      expect(subject.mayElevate('/srv/sing-box'), isTrue);
      expect(subject.mayElevate('/usr/bin/sing-box'), isFalse);
    });
  });
}
