/// Selects the proxy runtime for the host platform.
///
/// The contract and each platform implementation live in their own files; this
/// facade keeps the original import path stable for the app and its tests.
library;

import 'dart:io';

import 'android_proxy_controller.dart';
import 'linux_proxy_controller.dart';
import 'proxy_controller_base.dart';
import 'unsupported_proxy_controller.dart';
import 'windows_proxy_controller.dart';

export 'android_proxy_controller.dart';
export 'proxy_controller_base.dart';
export 'unsupported_proxy_controller.dart';

/// The controller for the host platform.
ProxyController createProxyController() {
  if (Platform.isAndroid) return AndroidProxyController();
  if (Platform.isLinux) return LinuxProxyController();
  if (Platform.isWindows) return WindowsProxyController();
  return UnsupportedProxyController(
    'The ${Platform.operatingSystem} runtime is not implemented yet. '
    'Config rendering and node management still work.',
  );
}
