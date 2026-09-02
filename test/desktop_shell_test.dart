/// The tray's repaint guard, and the strings its menu needs.
///
/// The guard is not an optimisation. [DesktopShell] listens to [AppState], which
/// notifies once a second while traffic flows, and rebuilding an AppIndicator
/// menu closes it under the cursor of whoever has it open. So the tray has to be
/// able to tell a change it draws from one it does not.
///
/// The rest of the tray needs a running panel and cannot be asserted here — what
/// this file can do is make sure the menu has something to say in both languages,
/// since a missing key there is an exception thrown outside the widget tree,
/// where nothing is watching for it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/l10n/app_localizations.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/platform/desktop_shell.dart';

/// A status with every field defaulted, so a test can vary just one.
ProxyStatusForTray status({
  bool connected = false,
  bool busy = false,
  bool hidden = false,
  AppLanguage language = AppLanguage.system,
  ProxyMode mode = ProxyMode.systemProxy,
}) =>
    ProxyStatusForTray(
      connected: connected,
      busy: busy,
      hidden: hidden,
      language: language,
      mode: mode,
    );

void main() {
  group('ProxyStatusForTray', () {
    test('a traffic sample is not a change', () {
      // The case the guard exists for: bytes moved, so AppState notified, but
      // nothing the tray draws is different. Redrawing here is what shuts an
      // open menu.
      expect(status(connected: true), status(connected: true));
      expect(status(connected: true).hashCode,
          status(connected: true).hashCode);
    });

    test('connecting is a change, because the icon carries it', () {
      expect(status(connected: true), isNot(status()));
    });

    test('going busy is a change, because the menu item disables', () {
      expect(status(busy: true), isNot(status()));
    });

    test('hiding the window is a change, because the verb flips', () {
      // "Hide window" has to become "Show window", or the only entry point on
      // Linux is mislabelled.
      expect(status(hidden: true), isNot(status()));
    });

    test('switching language is a change, because every label is rebuilt', () {
      expect(
        status(language: AppLanguage.chinese),
        isNot(status(language: AppLanguage.english)),
      );
    });

    test('switching proxy mode is a change, because the tick moves', () {
      expect(
        status(mode: ProxyMode.tun),
        isNot(status(mode: ProxyMode.systemProxy)),
      );
    });

    test('every proxy mode has a menu label', () {
      // The submenu builds one item per enum value with an exhaustive switch, so
      // a new mode is a compile error there — but only if it is also given a
      // string, which is what this checks.
      for (final locale in L10n.supportedLocales) {
        final strings = lookupL10n(locale);
        expect(strings.settingsProxyModeTun, isNotEmpty);
        expect(strings.settingsProxyModeSystemProxy, isNotEmpty);
        expect(strings.settingsProxyMode, isNotEmpty);
      }
    });
  });

  group('menu strings', () {
    for (final locale in L10n.supportedLocales) {
      test('${locale.languageCode} has every label the menu asks for', () {
        final strings = lookupL10n(locale);

        // Each of these is read from outside the widget tree, where a thrown
        // lookup would go unnoticed until a user right-clicked the icon.
        for (final (name, value) in [
          ('trayShowWindow', strings.trayShowWindow),
          ('trayHideWindow', strings.trayHideWindow),
          ('trayQuit', strings.trayQuit),
          ('trayTooltipConnected', strings.trayTooltipConnected),
          ('trayTooltipDisconnected', strings.trayTooltipDisconnected),
          ('actionConnect', strings.actionConnect),
          ('actionDisconnect', strings.actionDisconnect),
          ('settingsCloseToTray', strings.settingsCloseToTray),
          ('settingsCloseToTrayBody', strings.settingsCloseToTrayBody),
        ]) {
          expect(value, isNotEmpty, reason: '$name in ${locale.languageCode}');
        }
      });
    }

    test('show and hide are different words', () {
      // They label the same item in its two states; identical text would make
      // the menu look broken rather than toggling.
      for (final locale in L10n.supportedLocales) {
        final strings = lookupL10n(locale);
        expect(
          strings.trayShowWindow,
          isNot(strings.trayHideWindow),
          reason: locale.languageCode,
        );
      }
    });
  });
}
