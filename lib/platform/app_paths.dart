/// Filesystem locations owned by the app, from the platform side.
///
/// This is one `MethodChannel` call rather than a `path_provider` dependency:
/// that package's current Android implementation pulls in JNI bindings and build
/// hooks, which is a lot of build surface for a string the host already holds.
/// Asking the host directly also guarantees the answer is the same directory
/// libbox was set up with (`SetupOptions.basePath`), so app files and engine
/// state stay in one place.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// The channel name and method the Android host answers on.
///
/// Shared with the proxy runtime: one host, one channel.
const appControlChannel = 'singbox/control';
const dataDirMethod = 'dataDir';

const _channel = MethodChannel(appControlChannel);

/// The app's private data directory.
///
/// Android returns `filesDir`. Windows answers from the native runner so the
/// process controller and rule-set unpacker share one stable location. The
/// environment fallback keeps Windows development builds useful when the native
/// runner is older than the Dart bundle. Other desktop hosts continue to return
/// null until their native runtimes are implemented.
Future<String?> appDataDirectory() async {
  try {
    final hostPath = await _channel.invokeMethod<String>(dataDirMethod);
    if (hostPath != null && hostPath.isNotEmpty) return hostPath;
  } on Object {
    // Desktop runners from an older build do not expose the channel yet.
  }

  if (Platform.isWindows) {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base != null && base.isNotEmpty) return '$base\\SingBox Client';
  }
  return null;
}
