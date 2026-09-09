/// Responsive navigation shell shared by desktop and mobile layouts.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../version.dart';
import 'brand.dart';
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
            // Only the dashboard gets the signal field, and only while the
            // tunnel is up: it reports throughput, so it has nothing to say on
            // the settings or rules screens and would just be noise under text.
            final signals = connected && _tab == AppTab.home;
            if (constraints.maxWidth >= 840) {
              return Scaffold(
                body: _Backdrop(
                  state: widget.state,
                  accent: accent,
                  signals: signals,
                  child: Row(
                    children: [
                      _DesktopRail(
                        state: widget.state,
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
              body: _Backdrop(
                state: widget.state,
                accent: accent,
                signals: signals,
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

/// The console backdrop, fed the tunnel's throughput.
///
/// A separate widget so the traffic samples do not rebuild the page in front of
/// them. [AppState] notifies on every reading — about once a second while
/// connected — and the shell's own build produces the whole page subtree, so
/// listening up there would rebuild five screens' worth of widgets a second to
/// move some dots. The page arrives here as an already-built [child] that
/// [ListenableBuilder] passes through untouched.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.state,
    required this.accent,
    required this.signals,
    required this.child,
  });

  final AppState state;
  final Color accent;

  /// Whether this surface should carry the signal field at all.
  final bool signals;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!signals) {
      // Nothing to listen for: the grid and vignette do not depend on traffic,
      // so an idle or non-dashboard surface should not subscribe at all.
      return ConsoleBackground(accent: accent, child: child);
    }
    return ListenableBuilder(
      listenable: state,
      builder: (context, child) => ConsoleBackground(
        accent: accent,
        animate: true,
        showSignals: true,
        downlink: state.downlinkHistory,
        uplink: state.uplinkHistory,
        child: child,
      ),
      child: child,
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
    required this.state,
    required this.selected,
    required this.connected,
    required this.onSelected,
  });

  final AppState state;
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.bg, Color.lerp(palette.bg, palette.surface, .45)!],
        ),
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gap.md, bottom: Gap.xl),
            child: const _Wordmark(),
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
          Expanded(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white, Colors.transparent],
                stops: [0, .6, 1],
              ).createShader(bounds),
              child: ListenableBuilder(
                listenable: state,
                builder: (context, _) => SignalArtwork(
                  opacity: .65,
                  animate: connected && state.isConnected,
                  downlink: state.downlinkHistory,
                  uplink: state.uplinkHistory,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: Gap.md),
            child: Text(
              'v$appVersion',
              style: monoStyle(color: palette.faint, size: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// The launcher and sidebar share one recognisable mark.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;

    return Row(
      children: [
        const BrandMark(size: 44),
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
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                l10n.appTagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.faint,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
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
                Container(
                  width: 2,
                  height: 18,
                  decoration: BoxDecoration(
                    color: active ? palette.violetSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 10),
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
