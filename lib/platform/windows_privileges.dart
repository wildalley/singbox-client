/// Windows privilege escalation for TUN mode.
///
/// TUN requires administrator rights to create virtual network adapters and
/// modify routing tables. This module checks the current privilege level and
/// requests elevation via UAC when needed.
library;

import 'package:flutter/services.dart';

import 'app_paths.dart';

enum TunAuthorizationStatus {
  /// Administrator rights granted, TUN mode can proceed.
  granted,

  /// User declined the UAC prompt.
  declined,

  /// Elevation failed for an unknown reason.
  failed,

  /// UAC accepted and a new elevated app instance was launched.
  relaunching,
}

class WindowsPrivileges {
  const WindowsPrivileges();

  static const _channel = MethodChannel(appControlChannel);

  /// Returns true if the current process has administrator privileges.
  Future<bool> isRunningElevated() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRunningElevated');
      return result ?? false;
    } on Object {
      return false;
    }
  }

  /// Requests administrator privileges for TUN mode.
  ///
  /// If already elevated, TUN can proceed. Otherwise, shows a UAC prompt to
  /// restart with elevation. The pinned sing-box Windows runtime embeds its
  /// Wintun DLL, so there is no separate client-side driver file to probe.
  Future<TunAuthorizationStatus> requestTunPrivileges() async {
    // Check if already running elevated
    if (await isRunningElevated()) {
      return TunAuthorizationStatus.granted;
    }

    // Request elevation via UAC
    try {
      final result = await _channel.invokeMethod<bool>('requestElevation');
      if (result == true) {
        // The native runner starts a second, elevated app instance. The caller
        // must leave this unelevated process so the two instances do not both
        // try to own the runtime.
        return TunAuthorizationStatus.relaunching;
      }
      return TunAuthorizationStatus.declined;
    } on PlatformException {
      return TunAuthorizationStatus.declined;
    } on Object {
      return TunAuthorizationStatus.failed;
    }
  }
}
