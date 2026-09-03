import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/platform/app_paths.dart';
import 'package:singbox_client/platform/windows_privileges.dart';
import 'package:singbox_client/platform/windows_proxy_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(appControlChannel);
  var elevated = true;
  var elevationRequested = true;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'isRunningElevated' => elevated,
        'requestElevation' => elevationRequested,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('an elevated process can start TUN without an external Wintun DLL',
      () async {
    expect(
      await const WindowsPrivileges().requestTunPrivileges(),
      TunAuthorizationStatus.granted,
    );
  });

  test('accepted UAC is reported as a relaunch', () async {
    elevated = false;
    elevationRequested = true;

    expect(
      await WindowsPrivileges().requestTunPrivileges(),
      TunAuthorizationStatus.relaunching,
    );
  });

  test('dismissed UAC does not start TUN', () async {
    elevated = false;
    elevationRequested = false;

    expect(
      await WindowsPrivileges().requestTunPrivileges(),
      TunAuthorizationStatus.declined,
    );
  });

  test('system-proxy config enables WinINet while TUN leaves it optional', () {
    final controller = WindowsProxyController();
    addTearDown(controller.dispose);

    controller.prepareConfigForTests(jsonEncode({
      'inbounds': [
        {'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': 2080},
      ],
    }));
    expect(controller.usesSystemProxyForTests, isTrue);

    controller.prepareConfigForTests(jsonEncode({
      'inbounds': [
        {'type': 'tun'},
      ],
    }));
    expect(controller.usesSystemProxyForTests, isFalse);
  });
}
