/// The quit path, which has to put the desktop back before the process goes.
///
/// This exists because of a real hole. `dispose()` is synchronous, so it could
/// fire SIGTERM at the engine but could not wait for it, and it could not call
/// `gsettings` at all — restoring the desktop's proxy settings is async. So
/// quitting while connected in system-proxy mode killed the engine and left
/// GNOME pointed at 127.0.0.1:2080 with nothing behind it: every application on
/// the machine offline, with no window left to explain why.
///
/// The window's close button reaches this path too, which is why it is worth
/// pinning rather than leaving to a manual check.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/platform/desktop_shell.dart';
import 'package:singbox_client/platform/linux_proxy_controller.dart';
import 'package:singbox_client/platform/linux_system_proxy.dart';
import 'package:singbox_client/platform/single_instance.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController;

void main() {
  group('AppState.shutdown', () {
    test('asks the controller to unwind rather than only disposing it',
        () async {
      // The distinction the bug turned on. dispose() cannot restore the proxy
      // settings, so a quit path that calls it alone is the broken one.
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final controller = FakeProxyController();
      final state = AppState(storage: storage, controller: controller);

      await state.shutdown();

      expect(controller.didShutdown, isTrue);
    });

    test('is safe to call when nothing was ever connected', () async {
      // The ordinary case: opened, looked at, closed.
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final controller = FakeProxyController();
      final state = AppState(storage: storage, controller: controller);

      await expectLater(state.shutdown(), completes);
    });
  });

  group('closeToTray', () {
    test('defaults to on, so the tunnel survives a closed window', () async {
      expect(const AppSettings().closeToTray, isTrue);
    });

    test('survives a save', () async {
      final restored = AppSettings.fromJson(
        const AppSettings(closeToTray: false).toJson(),
      );

      expect(restored.closeToTray, isFalse);
    });

    test('copyWith carries it when something else changes', () {
      const settings = AppSettings(closeToTray: false);

      expect(settings.copyWith(mtu: 1400).closeToTray, isFalse);
      expect(settings.copyWith(closeToTray: true).closeToTray, isTrue);
    });

    test('settings written before the tray existed read as on', () {
      // The behaviour those users already had, and could not turn off.
      expect(AppSettings.fromJson(const {}).closeToTray, isTrue);
    });
  });

  group('LinuxProxyController.shutdown', () {
    test('restores the desktop even with no engine of its own running',
        () async {
      // An earlier unclean exit can leave the desktop pointed at our port while
      // this run never connected. Quitting is a chance to fix that, and the call
      // is cheap.
      final proxy = LinuxSystemProxy(
        backend: SystemProxyBackend.gnome,
        stateDirectory: null,
      );
      final controller = LinuxProxyController(
        systemProxy: proxy,
        binaryOverride: '/nonexistent',
      );

      await expectLater(controller.shutdown(), completes);
    });
  });

  group('DesktopShell.quit', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('releases the single-instance socket', () async {
      // The socket has to go before exit, or a restart sees a stale file.
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final controller = FakeProxyController();
      final state = AppState(storage: storage, controller: controller);
      final shell = DesktopShell(state);

      // A temp directory, not the real one: that holds the user's config and
      // credentials, and a second test file working in it at the same time is
      // how these start failing only when the whole suite runs.
      final dir = Directory.systemTemp.createTempSync('singbox_quit_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(
        await SingleInstance.claim(onActivate: () {}, directory: dir.path),
        isTrue,
        reason: 'nothing to release otherwise',
      );

      await shell.quit();

      // Released means a restart can claim. Had quit left the socket behind, this
      // would instead try to activate an instance that is already gone.
      expect(
        await SingleInstance.claim(onActivate: () {}, directory: dir.path),
        isTrue,
        reason: 'quit did not release the socket',
      );

      await SingleInstance.release();
    });

    test('is safe to call when the socket was never claimed', () async {
      // Not every platform has a data directory.
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final controller = FakeProxyController();
      final state = AppState(storage: storage, controller: controller);
      final shell = DesktopShell(state);

      await expectLater(shell.quit(), completes);
    });

    test('stops the engine and restores the desktop', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final controller = FakeProxyController();
      final state = AppState(storage: storage, controller: controller);
      final shell = DesktopShell(state);

      await shell.quit();

      // The engine is stopped and the desktop's proxy setting is put back.
      expect(controller.didShutdown, isTrue);
    });
  });
}
