/// [ProxyMode] as stored state.
///
/// The mode decides whether the rendered config asks for a privileged
/// interface, so a value that does not survive a save is a mode the user picked
/// and did not get. These cover the three ways it can be lost: dropped by
/// `copyWith`, not written by `toJson`, or misread on the way back in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/models/app_settings.dart';

void main() {
  test('the default is system proxy', () {
    // The mode that needs no privileges, so a fresh desktop install connects
    // without a polkit prompt. Android renders a tun whatever this says — see
    // the ConfigBuilder tests — so the default is the desktop's answer only.
    expect(const AppSettings().proxyMode, ProxyMode.systemProxy);
  });

  test('copyWith carries the mode when it is not the one being changed', () {
    const settings = AppSettings(proxyMode: ProxyMode.systemProxy);

    expect(settings.copyWith(mtu: 1400).proxyMode, ProxyMode.systemProxy);
    expect(settings.copyWith(proxyMode: ProxyMode.tun).proxyMode, ProxyMode.tun);
  });

  test('every mode round-trips through JSON', () {
    for (final mode in ProxyMode.values) {
      final restored = AppSettings.fromJson(
        AppSettings(proxyMode: mode).toJson(),
      );
      expect(restored.proxyMode, mode, reason: 'mode $mode');
    }
  });

  test('a missing or unknown stored value reads as system proxy', () {
    // Settings written before the mode existed have no key, and a value from a
    // newer build is not a reason to refuse to start. Either way the fallback is
    // the mode that cannot fail on privileges.
    expect(AppSettings.fromJson(const {}).proxyMode, ProxyMode.systemProxy);
    expect(
      AppSettings.fromJson(const {'proxy_mode': 'wireguard'}).proxyMode,
      ProxyMode.systemProxy,
    );
  });

  test('the stored name is the enum name, not its index', () {
    // An index would silently mean something else the moment a value is
    // inserted into the enum.
    expect(
      const AppSettings(proxyMode: ProxyMode.systemProxy).toJson()['proxy_mode'],
      'systemProxy',
    );
  });
}
