/// Granting the engine the capability a tun needs, through polkit.
///
/// Android gets its tun from `VpnService`: one dialog, and the fd arrives with
/// no capabilities involved. Linux has no such dialog — creating a tun device
/// and installing routes needs `CAP_NET_ADMIN` — so the equivalent is a file
/// capability on the `sing-box` binary, set once by root. `pkexec` is what asks:
/// polkit puts up the same authentication dialog the desktop uses for mounting a
/// disk or installing a package, and runs `setcap` on the other side of it.
///
/// File capabilities are applied by the kernel at `execve` of that file, and the
/// controller spawns `sing-box` as its own child, so granting them to the binary
/// is enough. Nothing here elevates the app itself, and no privileged helper is
/// installed: what survives is one attribute on one file.
///
/// The cost is that a package upgrade replaces the binary and the attribute goes
/// with it. That is not worth a helper daemon — the prompt simply comes back the
/// next time a tun is started.
library;

import 'dart:io';

import 'linux_system_proxy.dart' show CommandRunner;

/// The capability set a tun inbound needs.
///
/// `cap_net_admin` creates the interface and writes the routes; `cap_net_raw` is
/// what sing-box's own documentation pairs with it, for the sockets the tun
/// stack opens. `+ep` makes them effective without the binary having to raise
/// them itself.
const tunCapabilities = 'cap_net_admin,cap_net_raw';

/// What came of asking for [tunCapabilities].
enum TunAuthorization {
  /// Set on the binary — either already, or by the command just run.
  granted,

  /// The dialog was dismissed, or authentication failed. The user's answer, so
  /// nothing retries on its own.
  declined,

  /// Nothing to ask with: no `pkexec`, no `setcap`, or a binary this will not
  /// elevate. The manual command is the only route left.
  unavailable,

  /// The command ran and failed for some other reason.
  failed,
}

/// Reads and grants the file capabilities the tun mode needs.
class LinuxPrivileges {
  LinuxPrivileges({
    CommandRunner? runner,
    Iterable<String>? trustedRoots,
    Iterable<String>? searchPaths,
    bool Function(String path)? exists,
  })  : _run = runner ?? _runProcess,
        _exists = exists ?? _fileExists,
        _trustedRoots = List.unmodifiable(trustedRoots ?? defaultTrustedRoots),
        _searchPaths = List.unmodifiable(searchPaths ?? defaultSearchPaths);

  /// Directories whose contents may be handed to an elevated `setcap`.
  ///
  /// The binary path can come from `SINGBOX_BINARY`, which is process
  /// environment and therefore an input. Running `setcap` as root against an
  /// arbitrary path would turn that input into a capability grant on a file of
  /// the caller's choosing, so only the system locations a distribution installs
  /// an engine into are eligible. A binary outside them still runs — it just has
  /// to be granted by hand, which is a developer's own business.
  static const defaultTrustedRoots = [
    '/usr/bin/',
    '/usr/sbin/',
    '/usr/local/bin/',
    '/usr/local/sbin/',
    '/usr/lib/',
    '/bin/',
    '/sbin/',
    '/opt/',
  ];

  /// Where `pkexec`, `setcap` and `getcap` are looked for.
  ///
  /// Absolute paths rather than a `PATH` search: `pkexec` runs its argument as
  /// root, and resolving that argument through an environment variable the
  /// caller controls is how a PATH-injection bug is written.
  static const defaultSearchPaths = [
    '/usr/bin',
    '/usr/sbin',
    '/bin',
    '/sbin',
  ];

  final CommandRunner _run;

  /// Whether a tool is installed. Injectable so the argv can be asserted on a
  /// host that has no `pkexec` — a CI container, for one.
  final bool Function(String path) _exists;

  final List<String> _trustedRoots;
  final List<String> _searchPaths;

  /// Whether [binary] already carries [tunCapabilities].
  ///
  /// Null means the question could not be answered — no `getcap` on the system.
  /// Callers treat that as "start anyway": `getcap` and `setcap` ship in the same
  /// package, so where one is missing the other cannot fix anything either, and a
  /// polkit prompt that leads nowhere is worse than the engine's own error.
  Future<bool?> hasTunCapabilities(String binary) async {
    final getcap = _locate('getcap');
    if (getcap == null) return null;
    try {
      final result = await _run(getcap, [binary]);
      if (result.exitCode != 0) return null;
      return capabilitiesPresent('${result.stdout}');
    } on Object {
      return null;
    }
  }

  /// Asks polkit to set [tunCapabilities] on [binary].
  Future<TunAuthorization> grantTunCapabilities(String binary) async {
    if (!mayElevate(binary)) return TunAuthorization.unavailable;
    final argv = elevationCommand(binary);
    if (argv == null) return TunAuthorization.unavailable;
    try {
      final result = await _run(argv.first, argv.sublist(1));
      return outcomeOf(result.exitCode);
    } on Object {
      return TunAuthorization.unavailable;
    }
  }

  /// The full argv for the grant, or null when a tool is missing.
  ///
  /// Fixed positions, no shell: the path goes in as one argument, so a name with
  /// a space or a `;` in it is a filename and cannot be anything else.
  List<String>? elevationCommand(String binary) {
    final pkexec = _locate('pkexec');
    final setcap = _locate('setcap');
    if (pkexec == null || setcap == null) return null;
    return [pkexec, setcap, '$tunCapabilities+ep', binary];
  }

  /// Whether [binary] is one this will run an elevated `setcap` against.
  ///
  /// Absolute, named `sing-box`, and inside [defaultTrustedRoots]. See that
  /// constant for why the last condition is not paranoia.
  bool mayElevate(String binary) {
    if (!binary.startsWith('/') || binary.contains('/../')) return false;
    if (binary.split('/').last != 'sing-box') return false;
    return _trustedRoots.any(binary.startsWith);
  }

  /// Reads a `getcap` line.
  ///
  /// Two formats over libcap's life — `file cap_net_admin,cap_net_raw=ep` since
  /// 2.60, `file = cap_net_admin,cap_net_raw+ep` before it — so this looks for
  /// the names and for the effective flag rather than matching a whole line.
  /// Empty output is what an unprivileged binary produces.
  static bool capabilitiesPresent(String getcapOutput) {
    final text = getcapOutput.toLowerCase();
    if (!text.contains('cap_net_admin') || !text.contains('cap_net_raw')) {
      return false;
    }
    // Permitted but not effective (`=p`) would leave sing-box unable to use the
    // capabilities without raising them itself, which it does not do. Matching
    // the flag rather than a bare `ep` keeps a path like /opt/step/sing-box from
    // reading as one.
    return RegExp(r'[=+][a-z]*e').hasMatch(text);
  }

  /// What `pkexec`'s exit code means.
  ///
  /// 126 is a dismissed dialog and 127 is authorization it could not obtain —
  /// both the user's answer, not a fault. Anything else non-zero came from
  /// `setcap` itself.
  static TunAuthorization outcomeOf(int exitCode) => switch (exitCode) {
        0 => TunAuthorization.granted,
        126 || 127 => TunAuthorization.declined,
        _ => TunAuthorization.failed,
      };

  /// First existing `dir/name` from [_searchPaths].
  String? _locate(String name) {
    for (final dir in _searchPaths) {
      final candidate = '$dir/$name';
      if (_exists(candidate)) return candidate;
    }
    return null;
  }

  static bool _fileExists(String path) => File(path).existsSync();

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) =>
      Process.run(executable, arguments);
}
