/// Tray icon and window behaviour for the desktop builds.
///
/// A proxy is something you leave running, so the window should not be the thing
/// that holds it up. This puts an icon on the panel that says at a glance whether
/// the tunnel is up, and turns the window's close button into "hide" rather than
/// "quit".
///
/// Everything here is desktop-only. `tray_manager` and `window_manager` have no
/// Android implementation at all, so every entry point checks [isSupported]
/// first — calling through on Android throws MissingPluginException, which would
/// take the app down on launch.
///
/// The tray menu lives outside the widget tree, so it cannot read [L10n] from a
/// BuildContext. It resolves its own strings from the same setting the app does;
/// see [_strings].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../state/app_state.dart';
import 'single_instance.dart';

/// Whether this platform has a tray and a window to manage.
bool get isSupported =>
    !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

/// Whether the tray plugin reports pointer events and can pop its own menu.
///
/// False on Linux, where the tray is an AppIndicator: the panel owns the icon
/// and opens the menu itself, so the application is never told about a click and
/// `popUpContextMenu` is not implemented at all. Calling either would throw.
///
/// The consequence worth spelling out: on Linux the context menu is the *only*
/// way in, which is why "show window" is its first item rather than something a
/// left click would have handled.
bool get _hasPointerEvents => !Platform.isLinux;

/// Whether `setToolTip` exists on this platform's tray plugin.
///
/// Not on Linux — an AppIndicator has no tooltip, and the method is missing from
/// the plugin rather than being a no-op, so calling it throws
/// MissingPluginException.
bool get _hasToolTip => !Platform.isLinux;

/// Menu item ids. Strings rather than an enum because that is what the plugin
/// hands back to [onTrayMenuItemClick].
class _Item {
  static const toggleWindow = 'toggle_window';
  static const toggleConnection = 'toggle_connection';
  static const quit = 'quit';

  /// Proxy mode, one id per [ProxyMode] value.
  static String mode(ProxyMode mode) => 'mode_${mode.name}';

  /// The [ProxyMode] a [mode] id refers to, or null for any other item.
  static ProxyMode? modeOf(String? key) {
    for (final value in ProxyMode.values) {
      if (key == mode(value)) return value;
    }
    return null;
  }
}

/// Owns the tray icon, the window's close behaviour, and the quit path.
///
/// Created once from `main`, before `runApp`. It listens to [AppState] for the
/// connection status the icon reflects, so nothing in the UI layer needs to know
/// a tray exists.
class DesktopShell with TrayListener, WindowListener {
  DesktopShell(this.state);

  final AppState state;

  /// True once the window has been hidden, so the icon's menu can offer the
  /// right verb. Tracked rather than queried because [WindowManager.isVisible]
  /// is async and a menu has to be built synchronously.
  var _hidden = false;

  /// Set while [quit] runs, so a second close event during the async teardown
  /// does not start another one.
  var _quitting = false;

  /// True once the icon and its menu have actually gone on without throwing.
  ///
  /// Hiding the window is only safe if there is a way back. This session's bug
  /// is the argument for tracking it: the icon appeared, `setToolTip` threw
  /// before the menu was set, and the close button then hid the only window
  /// behind an icon that could not open anything. Nothing in the app could get
  /// it back — the user's only move was to launch a second copy.
  var _trayPainted = false;

  /// Whether the tray can be relied on as a way back to the window.
  ///
  /// [isSupported] says the platform has a tray; this says one is really there.
  bool get _reachableFromTray => isSupported && _trayPainted;

  ProxyStatusForTray? _lastPainted;

  /// Prepares the window before the first frame.
  ///
  /// Must run after `ensureInitialized` and before `runApp`: the close hook has
  /// to be in place before a user can reach the button, and setting it later
  /// leaves a window that quits.
  static Future<void> ensureWindowReady() async {
    if (!isSupported) return;
    await windowManager.ensureInitialized();
    // The app decides what closing means, not the window manager.
    await windowManager.setPreventClose(true);
  }

  /// Installs the tray icon and starts following [state].
  Future<void> start() async {
    if (!isSupported) return;
    trayManager.addListener(this);
    windowManager.addListener(this);
    state.addListener(_onStateChanged);
    await _tryPaint(force: true);
  }

  Future<void> dispose() async {
    if (!isSupported) return;
    state.removeListener(_onStateChanged);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } on Object catch (error) {
      debugPrint('tray destroy: $error');
    }
  }

  void _onStateChanged() {
    // Fire-and-forget: this runs on every notifyListeners, which includes a
    // traffic sample every second, and _paint returns early unless the status
    // it draws has actually changed.
    _tryPaint();
  }

  /// Runs [_paint], and swallows a failure after arranging for a retry.
  ///
  /// Two reasons this cannot simply throw. It is called unawaited, so the error
  /// would surface as an unhandled async exception with no one to act on it; and
  /// the tray is genuinely allowed to fail at startup — on GNOME the panel's
  /// AppIndicator support is an extension, and it is not guaranteed to be
  /// listening the instant the app is. Clearing the cached status is what turns
  /// the next state change into another attempt instead of a no-op.
  Future<void> _tryPaint({bool force = false}) async {
    try {
      await _paint(force: force);
    } on Object catch (error) {
      _lastPainted = null;
      debugPrint('tray: $error');
    }
  }

  /// Redraws the icon, tooltip and menu, but only when something they show moved.
  ///
  /// The guard matters more than it looks: without it every traffic sample would
  /// rebuild the menu, and on Linux rebuilding an appindicator menu while it is
  /// open closes it under the user's cursor.
  Future<void> _paint({bool force = false}) async {
    final status = ProxyStatusForTray(
      connected: state.isConnected,
      busy: state.isBusy,
      hidden: _hidden,
      language: state.settings.language,
      mode: state.settings.proxyMode,
    );
    if (!force && status == _lastPainted) return;
    _lastPainted = status;

    final strings = _strings(status.language);

    // The menu goes on first, and nothing optional is allowed to run before it.
    // On Linux it is the only way to reach the application at all, and an
    // earlier call that throws would leave an icon on the panel that does
    // nothing — which is exactly what a setToolTip before it used to cause.
    await trayManager.setContextMenu(
      Menu(
        items: [
          // First, and deliberately: on Linux there is no click event to open
          // the window with, so this item is the whole entry point.
          MenuItem(
            key: _Item.toggleWindow,
            label:
                status.hidden ? strings.trayShowWindow : strings.trayHideWindow,
          ),
          MenuItem.separator(),
          MenuItem(
            key: _Item.toggleConnection,
            label: status.connected
                ? strings.actionDisconnect
                : strings.actionConnect,
            // A start or stop already in flight; offering it again would queue
            // a second one against the same engine.
            disabled: status.busy,
          ),
          MenuItem.separator(),
          // Proxy mode as a checked group. Switching reloads the tunnel, which
          // is why the whole submenu is disabled mid-start or mid-stop rather
          // than only the item being switched away from.
          //
          // The `disabled` has to sit here rather than on the checkbox items:
          // tray_manager's Linux plugin creates a plain menu item, applies
          // `disabled` to it, and *then* replaces the pointer with a
          // GtkCheckMenuItem for the checkbox case — so a disabled checkbox is
          // silently still clickable. A disabled submenu works, because that
          // branch keeps the item it configured.
          MenuItem.submenu(
            label: strings.settingsProxyMode,
            disabled: status.busy,
            submenu: Menu(
              items: [
                for (final mode in ProxyMode.values)
                  MenuItem.checkbox(
                    key: _Item.mode(mode),
                    label: switch (mode) {
                      ProxyMode.tun => strings.settingsProxyModeTun,
                      ProxyMode.systemProxy =>
                        strings.settingsProxyModeSystemProxy,
                    },
                    checked: status.mode == mode,
                  ),
              ],
            ),
          ),
          MenuItem.separator(),
          MenuItem(key: _Item.quit, label: strings.trayQuit),
        ],
      ),
    );

    // The menu is on, which is the whole of what "reachable" means: it is the
    // one thing that can bring the window back. Recorded here rather than after
    // the icon and tooltip below, because neither of those affects whether the
    // user can get in — and treating a missing tooltip as an unreachable tray
    // would send the close button to quit for no reason.
    _trayPainted = true;

    await trayManager.setIcon(
      status.connected
          ? 'assets/tray/tray_connected.png'
          : 'assets/tray/tray_disconnected.png',
    );

    // Last, and only where it exists. The status is already carried by the
    // icon's colour, so this is the one part of the tray that can be missing
    // without costing the user anything.
    if (_hasToolTip) {
      await trayManager.setToolTip(
        status.connected
            ? strings.trayTooltipConnected
            : strings.trayTooltipDisconnected,
      );
    }
  }

  // --- tray events ----------------------------------------------------------

  /// Left click shows the window — on the platforms that report a left click.
  ///
  /// Never fires on Linux; see [_hasPointerEvents]. The menu's first item is the
  /// equivalent there.
  @override
  void onTrayIconMouseDown() {
    if (!_hasPointerEvents) return;
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // On Linux the panel opens the menu set by setContextMenu on its own, and
    // popUpContextMenu is not implemented — calling it throws rather than doing
    // nothing.
    if (!_hasPointerEvents) return;
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _Item.toggleWindow:
        _hidden ? _showWindow() : _hideWindow();
      case _Item.toggleConnection:
        state.toggleConnection();
      case _Item.quit:
        quit();
      default:
        // The proxy-mode group. Ignored when it is already the current mode:
        // applySettings reloads a running tunnel, and dropping every live
        // connection to arrive where you already were is not what a click on a
        // checked item asks for.
        final mode = _Item.modeOf(menuItem.key);
        if (mode != null && mode != state.settings.proxyMode) {
          state.applySettings(state.settings.copyWith(proxyMode: mode));
        }
    }
  }

  // --- window events --------------------------------------------------------

  @override
  void onWindowClose() {
    if (_quitting) return;
    // Two conditions, and the second is not a formality. The setting says the
    // user wants the tunnel to outlive the window; [_reachableFromTray] says
    // there is an icon that can bring the window back. Without a tray, hiding
    // would leave a process the user can neither see nor reach — so the close
    // button falls back to meaning what it says.
    //
    // Quitting always goes through [quit] rather than straight to exit, so the
    // tunnel stops and the desktop's proxy settings are put back.
    if (state.settings.closeToTray && _reachableFromTray) {
      _hideWindow();
    } else {
      quit();
    }
  }

  /// Raises the window because a second launch asked for it.
  ///
  /// Wired to [SingleInstance.claim]. A user who cannot reach the tray will try
  /// to start the app again; that attempt arrives here instead of becoming a
  /// second process.
  void activate() => _showWindow();

  /// Shows and focuses the window, leaving [_hidden] truthful either way.
  ///
  /// The flag is set after the call, not before: it decides whether the menu
  /// offers "show" or "hide", and a failed show that had already cleared it
  /// would leave the one item that can rescue the window labelled as if the
  /// window were already up.
  Future<void> _showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
      _hidden = false;
    } on Object catch (error) {
      debugPrint('window show: $error');
    }
    await _tryPaint();
  }

  /// Hides the window, and only claims to have done so if it worked.
  ///
  /// Same reasoning as [_showWindow] in reverse. A hide that throws while
  /// [_hidden] had already been set would leave a visible window whose tray menu
  /// says "Show window".
  Future<void> _hideWindow() async {
    try {
      await windowManager.hide();
      _hidden = true;
    } on Object catch (error) {
      debugPrint('window hide: $error');
    }
    await _tryPaint();
  }

  /// Stops the tunnel, puts the desktop back, then exits.
  ///
  /// [AppState.shutdown] is awaited rather than fired: on the desktop it is what
  /// restores the proxy settings, and a process that exits first leaves the
  /// machine pointing at a port with nothing behind it.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await dispose();
      await state.shutdown();
    } finally {
      // Release the guard last. A replacement process must not enter while this
      // one is still stopping its core or restoring the desktop proxy.
      await SingleInstance.release();
      // destroy() rather than close(): close would come back through
      // onWindowClose, which preventClose has told the window not to honour.
      //
      // Best effort, and deliberately last. Everything that matters has already
      // happened by this point — the engine is stopped and the desktop's proxy
      // settings are back — so a window that will not close is untidy rather
      // than harmful, and is not worth throwing out of the quit path over. It
      // also throws with no window plugin at all, which is how this runs under
      // test.
      try {
        await windowManager.destroy();
      } on Object catch (error) {
        debugPrint('window destroy: $error');
      }
    }
  }
}

/// The slice of app state the tray actually draws.
///
/// Exists so [DesktopShell] can tell a change that matters from the once-a-second
/// traffic notification that does not.
@immutable
class ProxyStatusForTray {
  const ProxyStatusForTray({
    required this.connected,
    required this.busy,
    required this.hidden,
    required this.language,
    this.mode = ProxyMode.systemProxy,
  });

  final bool connected;
  final bool busy;
  final bool hidden;
  final AppLanguage language;

  /// Which proxy mode is checked in the menu.
  final ProxyMode mode;

  @override
  bool operator ==(Object other) =>
      other is ProxyStatusForTray &&
      other.connected == connected &&
      other.busy == busy &&
      other.hidden == hidden &&
      other.language == language &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(connected, busy, hidden, language, mode);
}

/// Localised strings for the menu, resolved without a BuildContext.
///
/// [AppLanguage.system] follows the platform, matching what MaterialApp does
/// with a null locale — so the menu and the window agree on the language.
L10n _strings(AppLanguage language) {
  final tag = language.code ?? Platform.localeName.split(RegExp('[_.]')).first;
  return lookupL10n(
    L10n.supportedLocales.any((locale) => locale.languageCode == tag)
        ? Locale(tag)
        : const Locale('en'),
  );
}
