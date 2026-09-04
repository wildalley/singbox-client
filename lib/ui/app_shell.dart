/// Responsive navigation shell shared by desktop and mobile layouts.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../version.dart';
import 'components.dart';
import 'home_page.dart';
import 'logs_page.dart';
import 'nodes_page.dart';
import 'notice_text.dart';
import 'rules_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

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

  /// Surfaces one-shot notices from [AppState] as localized snackbars.
  void _onStateChanged() {
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
          content: Text(
            noticeText(L10n.of(context), notice),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: notice.isError
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

/// Keeps tab changes spatially continuous without making navigation feel like a
/// route push. Reduced-motion users get an immediate replacement.
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

/// Sidebar wordmark: the mark lights up while the tunnel is up.
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
