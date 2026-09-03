/// Keeps one copy of the app running, and gives a second launch a way to raise
/// the first one's window.
///
/// This exists because of how the tray fails. Once the close button hides the
/// window instead of quitting, the only way back in is the tray icon — and if
/// that icon is unresponsive, a user's next move is to launch the app again from
/// their menu. Without a guard that starts a second process which cannot bind
/// the engine's ports, leaving two instances fighting over one config while the
/// window they wanted is still hidden in the first.
///
/// So the second launch is not an error to refuse: it is the user asking for the
/// window. It says so over the socket and exits.
///
/// A local socket rather than a lock file because it answers both questions at
/// once — whether anyone is home, and how to talk to them. POSIX uses a Unix
/// socket in the app data directory. Windows uses a deterministic loopback TCP
/// port because Dart does not support Unix domain sockets there. A stale lock
/// file after a crash looks exactly like a live instance; a refused connection
/// is how both transports tell a stale endpoint from a live one.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

/// The single byte string a second launch sends. Content does not matter beyond
/// being distinguishable from a stray connection.
const _activate = 'activate';
const _activationAck = 'ok';

/// Passed to the elevated Windows child during a UAC handoff.
const elevatedRestartArgument = '--elevated-restart';

/// Socket file name, inside the app's own 0700 data directory.
const _socketName = 'instance.sock';

/// Guards against a second instance, on the platforms that need it.
class SingleInstance {
  const SingleInstance._();

  /// The listening socket held by the primary instance, so tests and shutdown
  /// can close it.
  static ServerSocket? _server;

  /// The Unix socket path held by [_server], or null for Windows' TCP endpoint.
  static String? _serverPath;

  /// Tries to become the one instance.
  ///
  /// Returns true when this process should carry on and run the app. In that
  /// case [onActivate] is called whenever a later launch asks for the window.
  ///
  /// Returns false when another instance already holds the socket. It has been
  /// asked to show its window, and the caller should exit without running the
  /// app — starting a UI would give the user a second window whose engine
  /// cannot bind its ports.
  ///
  /// Never throws. If neither connecting nor binding works the answer is true:
  /// a single instance is a convenience, and the failure mode that matters is a
  /// user with no window at all, not a user with two.
  /// [directory] overrides where the socket lives. Only for tests: without it
  /// they would bind, plant and delete files in the real data directory, which
  /// is where the user's rendered config and its node credentials live.
  /// [waitForExisting] is used by the elevated child during a handoff. It waits
  /// for the unelevated parent to exit instead of sending that parent an
  /// activation request, then claims the same socket normally.
  static Future<bool> claim({
    required void Function() onActivate,
    String? directory,
    bool waitForExisting = false,
  }) async {
    final path = await _socketPath(directory);
    if (path == null) return true;

    if (Platform.isWindows) {
      return _claimTcp(
        path,
        onActivate: onActivate,
        waitForExisting: waitForExisting,
      );
    }

    return _claimUnix(
      path,
      onActivate: onActivate,
      waitForExisting: waitForExisting,
    );
  }

  static Future<bool> _claimUnix(
    String path, {
    required void Function() onActivate,
    required bool waitForExisting,
  }) async {
    final address = InternetAddress(path, type: InternetAddressType.unix);

    if (waitForExisting && !await _waitForRelease(address, 0)) return false;

    // Ask first. A live instance answers, and that is also the only reliable
    // proof that the socket file belongs to a running process.
    if (!waitForExisting &&
        await _askToActivate(address, 0, expectAck: false)) {
      return false;
    }

    // Nothing answered. Any file here is a leftover from a process that did not
    // get to clean up, and it has to go before bind can take the address.
    try {
      final stale = File(path);
      if (stale.existsSync()) stale.deleteSync();
    } on Object {
      // Not ours to delete, or already gone. bind decides what happens next.
    }

    try {
      final server = await ServerSocket.bind(address, 0);
      _server = server;
      _serverPath = path;
      _listen(server, onActivate);
      return true;
    } on Object {
      // Another launch may have won the bind race after our first probe. Ask
      // once more before falling back to an unguarded launch.
      return await _askToActivate(address, 0, expectAck: false) ? false : true;
    }
  }

  static Future<bool> _claimTcp(
    String path, {
    required void Function() onActivate,
    required bool waitForExisting,
  }) async {
    final port = _activationPort(path);
    final address = InternetAddress.loopbackIPv4;

    if (waitForExisting && !await _waitForRelease(address, port)) return false;

    // A live instance answers with our small acknowledgement. This avoids
    // treating an unrelated service that happens to occupy the derived port as
    // the app instance.
    if (!waitForExisting &&
        await _askToActivate(address, port, expectAck: true)) {
      return false;
    }

    try {
      final server = await ServerSocket.bind(address, port);
      _server = server;
      _serverPath = null;
      _listen(server, onActivate);
      return true;
    } on Object {
      // A port collision is the Windows equivalent of a failed Unix bind. The
      // app remains usable even when the convenience guard is unavailable. A
      // second probe distinguishes our own listener from an unrelated service.
      return await _askToActivate(address, port, expectAck: true)
          ? false
          : true;
    }
  }

  static void _listen(ServerSocket server, void Function() onActivate) {
    server.listen(
      (socket) {
        // Read one framed message, then act. The payload is checked so an
        // unrelated connection cannot raise the window. The acknowledgement
        // also disambiguates a Windows TCP port collision from our listener.
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .then((message) async {
          if (message.trim() != _activate) return;
          try {
            socket.write('$_activationAck\n');
            // Invoke immediately after the write. A launcher is allowed to
            // close as soon as it receives the acknowledgement; waiting for
            // flush first can make that close race skip the activation.
            onActivate();
            await socket.flush();
          } on Object {
            // The launching process may have closed immediately after sending.
          }
        }, onError: (_) {}).whenComplete(() => socket.destroy());
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  /// Stops listening and removes the Unix socket file when there is one.
  ///
  /// Called from the quit path. A socket left behind is not fatal — the next
  /// launch finds nothing answering and clears it — but leaving one is untidy
  /// in a directory that also holds the config.
  static Future<void> release() async {
    final server = _server;
    _server = null;
    final path = _serverPath;
    _serverPath = null;
    if (server == null) return;
    try {
      await server.close();
    } on Object {
      // Already gone.
    }
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } on Object {
        // Someone else's now, or already removed.
      }
    }
  }

  /// Whether a live instance answered and was asked to show its window.
  static Future<bool> _askToActivate(
    InternetAddress address,
    int port, {
    required bool expectAck,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        address,
        port,
        // Short: this runs before the first frame of a launch. A hang here is a
        // launch that appears to do nothing.
        timeout: const Duration(seconds: 2),
      );
      socket.write('$_activate\n');
      await socket.flush();
      // POSIX has an app-specific socket pathname, so a successful connect is
      // enough to identify our instance. Do not require an acknowledgement
      // here: this keeps an already-running pre-TCP version compatible during
      // an upgrade. Windows needs the response because its derived TCP port
      // can be occupied by an unrelated local service.
      if (!expectAck) return true;
      final response = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));
      return response.trim() == _activationAck;
    } on Object {
      // Refused (a stale socket file), absent, or timed out.
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Waits for the process that owns [address] to exit during elevation.
  ///
  /// The child cannot claim the socket while the parent still owns it, but it
  /// must not turn a slow UAC handoff into a second unguarded app instance.
  static Future<bool> _waitForRelease(InternetAddress address, int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _socketIsLive(address, port)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  static Future<bool> _socketIsLive(InternetAddress address, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        address,
        port,
        timeout: const Duration(milliseconds: 250),
      );
      return true;
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Maps the stable data-directory identity to a user-space TCP port.
  static int _activationPort(String path) {
    var hash = 2166136261;
    for (final unit in path.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 49152 + hash % 16384;
  }

  /// Where the socket lives, or null when there is no data directory to put it
  /// in — in which case the app runs unguarded rather than not at all.
  static Future<String?> _socketPath(String? directory) async {
    final dir = directory ?? await appDataDirectory();
    if (dir == null) return null;
    return '$dir${Platform.pathSeparator}$_socketName';
  }

  /// The socket path under [directory], for a test that plants or inspects the
  /// file.
  ///
  /// Deliberately the same call the guard itself uses rather than a second
  /// derivation: a copy would drift and the test would then be asserting against
  /// a path the app never touches.
  @visibleForTesting
  static Future<String?> socketPathForTests(String directory) =>
      _socketPath(directory);
}
