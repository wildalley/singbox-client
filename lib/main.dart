/// SingBox Client entry point.
///
/// Wires storage and the platform proxy controller into [AppState], then hosts
/// the responsive shell: bottom navigation on mobile, a persistent rail on
/// desktop-sized windows.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/rule_sets.dart';
import 'data/storage.dart';
import 'platform/desktop_shell.dart';
import 'platform/single_instance.dart';
import 'l10n/app_localizations.dart';
import 'models/app_settings.dart';
import 'platform/proxy_controller.dart';
import 'state/app_state.dart';
import 'ui/home_page.dart';
import 'ui/logs_page.dart';
import 'ui/nodes_page.dart';
import 'ui/notice_text.dart';
import 'ui/rules_page.dart';
import 'ui/settings_page.dart';
import 'ui/components.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'version.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // The shell does not exist yet — it needs AppState, which needs storage — so
  // the guard is handed a callback that defers to it once it does. An activation
  // arriving in that window is dropped, which is the right answer: the first
  // instance is still starting, and its window is about to appear anyway.
  DesktopShell? shell;
  final elevatedRestart =
      Platform.isWindows && args.contains(elevatedRestartArgument);
  if (isSupported &&
      !await SingleInstance.claim(
        onActivate: () => shell?.activate(),
        waitForExisting: elevatedRestart,
      )) {
    // Another instance holds the socket and has been asked to show its window.
    // Nothing has been initialised yet, so there is nothing to unwind.
    exit(0);
  }

  // Before runApp, and before the user can reach the close button: the window
  // has to be told not to quit on its own first. No-op off the desktop.
  await DesktopShell.ensureWindowReady();
  final storage = await Storage.open();
  // Before the first config is rendered: with the rule-sets on disk the engine
  // starts without reaching the network, which is the difference between
  // connecting and not on a filtered or offline link.
  final ruleSetDir = await BundledRuleSets.prepare();
  final state = AppState(
    storage: storage,
    controller: createProxyController(),
    ruleSetDir: ruleSetDir,
  );
  runApp(SingBoxApp(state: state));
  // After runApp so the icon does not delay the first frame. Unawaited for the
  // same reason: a panel that is slow to accept an indicator must not hold up
  // the window.
  shell = DesktopShell(state);
  unawaited(shell.start());
  // The unelevated process launched the UAC child on behalf of a connection
  // request, then exited. The child has the same persisted nodes/settings, so
  // resume that request instead of leaving the user at a disconnected screen
  // that requires a second manual click.
  if (elevatedRestart) unawaited(state.connect());
}

/// Hosts the shell. [state] is owned by the caller (`main`, or a test), which
/// is also responsible for disposing it.
class SingBoxApp extends StatefulWidget {
  const SingBoxApp({super.key, required this.state});

  final AppState state;

  @override
  State<SingBoxApp> createState() => _SingBoxAppState();
}

class _SingBoxAppState extends State<SingBoxApp> with WidgetsBindingObserver {
  /// The two settings [MaterialApp] actually reads, as a notifier that only
  /// fires when one of them changes.
  ///
  /// AppState notifies for everything — a traffic sample a second, a log line per
  /// connection — and MaterialApp sits above Theme, Localizations and every page,
  /// so rebuilding it on those was the most expensive listener in the app for the
  /// least reason. This narrows it to the two values it uses.
  late final _presentation =
      ValueNotifier<({AppThemeMode theme, AppLanguage language})>(_read());

  ({AppThemeMode theme, AppLanguage language}) _read() => (
        theme: widget.state.settings.themeMode,
        language: widget.state.settings.language,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_stopForLifecycle());
    }
  }

  /// The backstop for a detach that never reached [DesktopShell.quit] — a
  /// session ending, or the process being closed from outside the window.
  Future<void> _stopForLifecycle() async {
    try {
      await widget.state.disconnect();
    } on Object {
      // Already shut down, most likely because the quit path got here first.
      // Both desktop runtimes still restore the system proxy at the next start,
      // and the Windows runner has its Job Object fallback besides.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_onStateChanged);
    _presentation.dispose();
    super.dispose();
  }

  /// A record, so ValueNotifier's own equality check does the filtering: the
  /// value only differs when one of the two fields does.
  void _onStateChanged() => _presentation.value = _read();

  AppState get state => widget.state;

  /// Built once and reused. Neither depends on anything that changes at runtime,
  /// and rebuilding the pair measured about 108us — paid on every log line, for
  /// two objects that came out identical every time.
  static final _light = buildAppTheme(Brightness.light);
  static final _dark = buildAppTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    // Rebuilds only when the theme or the locale actually changes.
    //
    // Not a plain listen on AppState: that notifies on every traffic sample and
    // every log line, and each one rebuilt MaterialApp — which rebuilds the
    // Localizations and Theme scopes and everything under them. The pages that
    // need live data listen for themselves.
    return ValueListenableBuilder<({AppThemeMode theme, AppLanguage language})>(
      valueListenable: _presentation,
      builder: (context, settings, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => L10n.of(context).appTitle,
          theme: _light,
          darkTheme: _dark,
          themeMode: switch (settings.theme) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.supportedLocales,
          // null lets the platform locale win, falling back to English.
          locale: settings.language.code == null
              ? null
              : Locale(settings.language.code!),
          home: AppShell(state: widget.state),
        );
      },
    );
  }
}

/// Navigation destinations, shared by both layouts.
enum AppTab {
  home(Icons.home_outlined, Icons.home_rounded),
  nodes(Icons.hub_outlined, Icons.hub_rounded),
  rules(Icons.alt_route_outlined, Icons.alt_route_rounded),
  logs(Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  settings(Icons.settings_outlined, Icons.settings_rounded);

  const AppTab(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String label(L10n l10n) => switch (this) {
        AppTab.home => l10n.navHome,
        AppTab.nodes => l10n.navNodes,
        AppTab.rules => l10n.navRules,
        AppTab.logs => l10n.navLogs,
        AppTab.settings => l10n.navSettings,
      };

  /// The rail is wider than the tab bar, so Home gets a fuller label there.
  String railLabel(L10n l10n) =>
      this == AppTab.home ? l10n.railOverview : label(l10n);
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _tab = AppTab.home;

  /// The only thing the shell's own chrome reads from state.
  ///
  /// The rail, the navigation bar and the [ConsoleBackground] all key off the
  /// accent colour, which follows this one bool. Kept as a notifier so they stop
  /// rebuilding on the things they do not read — a traffic sample a second, and a
  /// log line per connection while the engine is busy.
  late final _connected = ValueNotifier<bool>(widget.state.isConnected);

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _connected.dispose();
    super.dispose();
  }

  /// Surfaces one-shot notices from [AppState] as snackbars, localizing the
  /// notice kind here since the state layer holds no BuildContext.
  void _onStateChanged() {
    // ValueNotifier drops a write that equals the current value, so this only
    // rebuilds the chrome when the connection actually changed.
    _connected.value = widget.state.isConnected;
    final notice = widget.state.takeNotice();
    if (notice == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final palette = context.palette;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          // Engine errors run to several hundred characters — a sing-box
          // rule-set failure quotes a URL and a socket address per rule-set.
          // Unbounded, that laid the whole string over the dial, the connect
          // button and the traffic card. The full text is in the logs page;
          // this is the alert, not the report.
          content: Text(
            noticeText(L10n.of(context), notice),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: notice.isError
              // Pre-composited, not translucent. At 18% alpha the dial and its
              // rings read straight through the bar, which is what made one
              // long error look like two overlapping copies of itself.
              ? Color.alphaBlend(
                  palette.danger.withValues(alpha: .18),
                  palette.surface3,
                )
              : null,
        ),
      );
  }

  void _goToTab(AppTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // Built here, once per tab change, rather than inside a builder that runs on
    // every notification. Each page subscribes to what it actually reads — see
    // PageBody — so rebuilding all of them from the shell was redrawing four
    // screens nobody was looking at for every log line.
    final page = switch (_tab) {
      AppTab.home => HomePage(
          state: widget.state,
          onOpenNodes: () => _goToTab(AppTab.nodes),
        ),
      AppTab.nodes => NodesPage(state: widget.state),
      AppTab.rules => RulesPage(state: widget.state),
      AppTab.logs => LogsPage(state: widget.state),
      AppTab.settings => SettingsPage(
          state: widget.state,
          onOpenLogs: () => _goToTab(AppTab.logs),
        ),
    };

    return ValueListenableBuilder<bool>(
      valueListenable: _connected,
      builder: (context, connected, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final accent =
                connected ? context.palette.mint : context.palette.violet;
            final transitioningPage = _TabTransition(
              tab: _tab,
              child: page,
            );
            if (constraints.maxWidth >= 840) {
              return Scaffold(
                body: ConsoleBackground(
                  accent: accent,
                  child: Row(
                    children: [
                      _DesktopRail(
                        selected: _tab,
                        connected: connected,
                        onSelected: _goToTab,
                      ),
                      Expanded(child: transitioningPage),
                    ],
                  ),
                ),
              );
            }

            return Scaffold(
              body: ConsoleBackground(
                accent: accent,
                child: SafeArea(bottom: false, child: transitioningPage),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab.index,
                onDestinationSelected: (index) =>
                    _goToTab(AppTab.values[index]),
                destinations: [
                  for (final tab in AppTab.values)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selectedIcon),
                      label: tab.label(l10n),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Keeps tab changes spatially continuous without making a navigation action
/// feel like a route push. The outgoing page is still visible for one short
/// beat, so a toolbar changing into another one reads as intentional rather
/// than as a redraw. Reduced-motion users get an immediate replacement.
class _TabTransition extends StatelessWidget {
  const _TabTransition({required this.tab, required this.child});

  final AppTab tab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = motionOf(context, Motion.normal);
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.012, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(tab), child: child),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.selected,
    required this.connected,
    required this.onSelected,
  });

  final AppTab selected;
  final bool connected;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;

    return Container(
      width: 240,
      padding: const EdgeInsets.fromLTRB(Gap.lg, 26, Gap.md, Gap.xl),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gap.md, bottom: Gap.xl),
            child: _Wordmark(connected: connected),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
            child: StatusPill(
              label: connected ? l10n.stageConnected : l10n.stageDisconnected,
              color: connected ? palette.mint : palette.muted,
            ),
          ),
          const SizedBox(height: 24),
          for (final tab in AppTab.values)
            _RailItem(
              tab: tab,
              active: tab == selected,
              onTap: () => onSelected(tab),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(left: Gap.md),
            child: Text(
              'v$appVersion',
              style: TextStyle(color: palette.faint, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sidebar wordmark: the mark lights up while the tunnel is up, so the rail
/// carries connection state even when the pill below it is scrolled past.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final lit = connected ? palette.mint : palette.violet;

    return Row(
      children: [
        AnimatedContainer(
          duration: Motion.normal,
          curve: Motion.curve,
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // Opaque, for the same reason as the connection dial's disc: the
            // glow below would otherwise show through a 13%-alpha fill and
            // wash out the mark sitting on it. The rail has no card under it,
            // so this composites against the page, not surface.
            color: Color.alphaBlend(lit.withValues(alpha: .13), palette.bg),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: lit.withValues(alpha: .32)),
            boxShadow: connected
                ? glow(
                    lit,
                    intensity:
                        0.5 * glowIntensity(Theme.of(context).brightness),
                  )
                : null,
          ),
          child: Icon(Icons.blur_on_rounded, color: lit, size: 18),
        ),
        const SizedBox(width: Gap.md),
        // The name sits above a tracked-out label, the way the dashboard's
        // section headers read. Tracking is positive here: at 9px the display
        // face needs the extra air to stay legible as a label.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appShortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontFamilyFallback: AppFonts.cjkFallback,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                l10n.railOverview.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.faint,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            padding:
                const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? palette.violet.withValues(alpha: .16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Icon(
                  active ? tab.selectedIcon : tab.icon,
                  size: 19,
                  color: active ? palette.violetSoft : palette.muted,
                ),
                const SizedBox(width: Gap.md),
                Text(
                  tab.railLabel(L10n.of(context)),
                  style: TextStyle(
                    color: active ? palette.text : palette.muted,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
