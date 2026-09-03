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

  /// wintun.dll is missing from the application directory.
  driverMissing,

  /// Elevation failed for an unknown reason.
  failed,
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
  /// If already elevated, checks for wintun.dll and returns [granted].
  /// Otherwise, shows UAC prompt to restart with elevation.
  Future<TunAuthorizationStatus> requestTunPrivileges() async {
    // Check if already running elevated
    if (await isRunningElevated()) {
      // Verify wintun.dll exists
      if (await _hasWintunDriver()) {
        return TunAuthorizationStatus.granted;
      }
      return TunAuthorizationStatus.driverMissing;
    }

    // Request elevation via UAC
    try {
      final result = await _channel.invokeMethod<bool>('requestElevation');
      if (result == true) {
        // The app will restart elevated, so this process should exit
        return TunAuthorizationStatus.granted;
      }
      return TunAuthorizationStatus.declined;
    } on PlatformException {
      return TunAuthorizationStatus.declined;
    } on Object {
      return TunAuthorizationStatus.failed;
    }
  }

  Future<bool> _hasWintunDriver() async {
    // TODO: Implement wintun.dll detection
    // For now, assume it's available when running elevated
    return true;
  }
}
