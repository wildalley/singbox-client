/// Filesystem locations owned by the app, from the platform side.
///
/// This is one `MethodChannel` call rather than a `path_provider` dependency:
/// that package's current Android implementation pulls in JNI bindings and build
/// hooks, which is a lot of build surface for a string the host already holds.
/// Asking the host directly also guarantees the answer is the same directory
/// libbox was set up with (`SetupOptions.basePath`), so app files and engine
/// state stay in one place.
library;

import 'package:flutter/services.dart';

/// The channel name and method the Android host answers on.
///
/// Shared with the proxy runtime: one host, one channel.
const appControlChannel = 'singbox/control';
const dataDirMethod = 'dataDir';

const _channel = MethodChannel(appControlChannel);

/// The app's private data directory, or null where there is no host to ask.
///
/// Android returns `filesDir`. The desktop platforms have no host handler — no
/// proxy runtime either, see `UnsupportedProxyController` — so the channel
/// throws and they get null; callers fall back rather than fail.
Future<String?> appDataDirectory() async {
  try {
    return await _channel.invokeMethod<String>(dataDirMethod);
  } on Object {
    return null;
  }
}
