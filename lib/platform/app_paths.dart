/// Filesystem locations owned by the app.
///
/// The Android answer comes over one `MethodChannel` call rather than a
/// `path_provider` dependency: that package's current Android implementation
/// pulls in JNI bindings and build hooks, which is a lot of build surface for a
/// string the host already holds. Asking the host directly also guarantees the
/// answer is the same directory libbox was set up with
/// (`SetupOptions.basePath`), so app files and engine state stay in one place.
///
/// The desktop hosts answer nothing, so the path is derived here instead, from
/// the XDG base directory spec. Same reasoning as above, one step further: the
/// rule is short enough to write out, and doing so keeps the dependency out.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// The channel name and method the Android host answers on.
///
/// Shared with the proxy runtime: one host, one channel.
const appControlChannel = 'singbox/control';
const dataDirMethod = 'dataDir';

/// Directory name under the desktop data root. Not the package name — this one
/// is user-visible in `~/.local/share`.
const desktopDataDirName = 'singbox-client';

const _channel = MethodChannel(appControlChannel);

/// The app's private data directory, or null when there is nowhere to put one.
///
/// Android returns `filesDir`. On Linux and Windows the channel throws — there
/// is no host handler — and the path is computed and created here. Everything
/// that lands in it is private: the rendered config carries node credentials
/// and the Clash API secret, so the directory is created 0700 on POSIX.
///
/// [environment] overrides the process environment, so a test can point the
/// derivation at a temp directory instead of the real `~/.local/share`.
Future<String?> appDataDirectory({Map<String, String>? environment}) async {
  try {
    final fromHost = await _channel.invokeMethod<String>(dataDirMethod);
    if (fromHost != null && fromHost.isNotEmpty) return fromHost;
  } on Object {
    // No host handler: a desktop build. Fall through.
  }
  return _desktopDataDirectory(environment ?? Platform.environment);
}

/// Resolves and creates the desktop data directory.
///
/// Returns null rather than throwing: callers treat a missing directory as "no
/// local rule-sets" and carry on, and the Linux runtime reports it as an
/// engine error, which is more useful than a crash at startup.
Future<String?> _desktopDataDirectory(Map<String, String> env) async {
  final root = _dataRoot(env);
  if (root == null) return null;
  final dir = Directory('$root${Platform.pathSeparator}$desktopDataDirName');
  try {
    final fresh = !dir.existsSync();
    if (fresh) await dir.create(recursive: true);
    // Dart has no chmod. Only on a fresh directory: a user who widened the
    // permissions themselves is not overruled on every launch.
    if (fresh && !Platform.isWindows) await restrictToOwner(dir.path);
    return dir.path;
  } on Object {
    return null;
  }
}

/// `$XDG_DATA_HOME`, `~/.local/share`, or the Windows equivalent.
String? _dataRoot(Map<String, String> env) {
  if (Platform.isWindows) {
    return env['APPDATA'] ?? env['USERPROFILE'];
  }
  final xdg = env['XDG_DATA_HOME'];
  // The spec says a relative XDG_DATA_HOME must be ignored.
  if (xdg != null && xdg.startsWith('/')) return xdg;
  final home = env['HOME'];
  return home == null || home.isEmpty ? null : '$home/.local/share';
}

/// Drops group and other permissions from [path]. Best effort: failure means
/// the file keeps the umask's answer, which is not a reason to refuse to run.
Future<void> restrictToOwner(String path, {bool file = false}) async {
  if (Platform.isWindows) return;
  try {
    await Process.run('chmod', [file ? '600' : '700', path]);
  } on Object {
    // No chmod on PATH. Nothing else to try.
  }
}
