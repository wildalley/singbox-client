/// SingBox Client entry point.
///
/// Wires storage and the platform proxy controller into [AppState], then hosts
/// the responsive shell: bottom navigation on mobile, a persistent rail on
/// desktop-sized windows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/storage.dart';
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
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  runApp(
    SingBoxApp(
      state: AppState(
        storage: storage,
        controller: createProxyController(),
      ),
    ),
  );
}

/// Hosts the shell. [state] is owned by the caller (`main`, or a test), which
/// is also responsible for disposing it.
class SingBoxApp extends StatelessWidget {
  const SingBoxApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // Rebuild on settings changes: theme and locale both come from AppState.
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final settings = state.settings;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => L10n.of(context).appTitle,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: switch (settings.themeMode) {
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
          home: AppShell(state: state),
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

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  /// Surfaces one-shot notices from [AppState] as snackbars, localizing the
  /// notice kind here since the state layer holds no BuildContext.
  void _onStateChanged() {
    final notice = widget.state.takeNotice();
    if (notice == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final palette = context.palette;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(noticeText(L10n.of(context), notice)),
          backgroundColor:
              notice.isError ? palette.danger.withValues(alpha: .18) : null,
        ),
      );
  }

  void _goToTab(AppTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
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

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 840) {
              return Scaffold(
                body: Row(
                  children: [
                    _DesktopRail(
                      selected: _tab,
                      connected: widget.state.isConnected,
                      onSelected: _goToTab,
                    ),
                    Expanded(child: page),
                  ],
                ),
              );
            }

            return Scaffold(
              body: SafeArea(bottom: false, child: page),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab.index,
                onDestinationSelected: (index) => _goToTab(AppTab.values[index]),
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
      width: 218,
      padding: const EdgeInsets.fromLTRB(Gap.lg, 26, Gap.md, Gap.xl),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gap.md, bottom: 28),
            child: Row(
              children: [
                Icon(Icons.blur_on_rounded, color: palette.violet, size: 22),
                const SizedBox(width: 10),
                Text(
                  l10n.appShortName,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
            child: StatusPill(
              label:
                  connected ? l10n.stageConnected : l10n.stageDisconnected,
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
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding:
                const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? palette.violet.withValues(alpha: .16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
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

/// Shown in the rail and in Settings; keep in sync with pubspec `version`.
const appVersion = '0.1.0';
