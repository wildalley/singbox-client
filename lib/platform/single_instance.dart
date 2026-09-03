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
/// A Unix socket rather than a lock file because it answers both questions at
/// once — whether anyone is home, and how to talk to them. A stale lock file
/// after a crash looks exactly like a live instance; a stale *socket* refuses
/// the connection, which is how this tells the two apart.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

/// The single byte string a second launch sends. Content does not matter beyond
/// being distinguishable from a stray connection.
const _activate = 'activate';

/// Socket file name, inside the app's own 0700 data directory.
const _socketName = 'instance.sock';

/// Guards against a second instance, on the platforms that need it.
class SingleInstance {
  const SingleInstance._();

  /// The listening socket held by the primary instance, so tests and shutdown
  /// can close it.
  static ServerSocket? _server;

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
  static Future<bool> claim({
    required void Function() onActivate,
    String? directory,
  }) async {
    final path = await _socketPath(directory);
    if (path == null) return true;
    final address = InternetAddress(path, type: InternetAddressType.unix);

    // Ask first. A live instance answers, and that is also the only reliable
    // proof that the socket file belongs to a running process.
    if (await _askToActivate(address)) return false;

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
      server.listen(
        (socket) {
          // Drain, then act. The payload is only checked so an unrelated
          // connection cannot raise the window.
          socket.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk))
              .then((bytes) {
            if (String.fromCharCodes(bytes).trim() == _activate) onActivate();
          }, onError: (_) {})
              .whenComplete(() => socket.destroy());
        },
        onError: (_) {},
        cancelOnError: false,
      );
      return true;
    } on Object {
      // No socket, so no guard — but the app itself is fine to run.
      return true;
    }
  }

  /// Stops listening and removes the socket file.
  ///
  /// Called from the quit path. A socket left behind is not fatal — the next
  /// launch finds nothing answering and clears it — but leaving one is untidy
  /// in a directory that also holds the config.
  static Future<void> release() async {
    final server = _server;
    _server = null;
    if (server == null) return;
    final path = server.address.address;
    try {
      await server.close();
    } on Object {
      // Already gone.
    }
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // Someone else's now, or already removed.
    }
  }

  /// Whether a live instance answered and was asked to show its window.
  static Future<bool> _askToActivate(InternetAddress address) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        address,
        0,
        // Short: this runs before the first frame of a launch. A hang here is a
        // launch that appears to do nothing.
        timeout: const Duration(seconds: 2),
      );
      socket.write(_activate);
      await socket.flush();
      return true;
    } on Object {
      // Refused (a stale socket file), absent, or timed out.
      return false;
    } finally {
      socket?.destroy();
    }
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
