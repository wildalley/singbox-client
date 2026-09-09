/// Settings screen: subscriptions, network behaviour, appearance, diagnostics.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/subscription.dart';
import '../platform/android_apps.dart';
import '../state/app_state.dart';
import '../version.dart';
import 'clock.dart';
import 'import_sheet.dart';
import 'json_highlight.dart';
import 'notice_text.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage(
      {super.key, required this.state, required this.onOpenLogs});

  final AppState state;
  final VoidCallback onOpenLogs;

  @override
  Widget build(BuildContext context) => PageBody(state: state, builder: _build);

  Widget _build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = state.settings;

    return PageFrame(
      title: l10n.settingsTitle,
      subtitle: l10n.settingsSubtitle,
      children: [
        SettingGroup(
          title: l10n.settingsSubscriptions,
          rows: [
            for (final subscription in state.subscriptions)
              _SubscriptionRow(state: state, subscription: subscription),
            SettingRow(
              icon: Icons.add_circle_outline,
              title: l10n.settingsAddSubscription,
              subtitle: l10n.settingsAddSubscriptionBody,
              onTap: () => showImportSheet(context, state),
            ),
          ],
        ),
        // Order follows how often a setting is reached for: what the tunnel is,
        // then how names resolve, then cosmetics. Appearance used to sit second,
        // above the settings that actually change how traffic moves.
        SettingGroup(
          title: l10n.settingsProxy,
          rows: [
            // Android's tun arrives with the VpnService dialog, so there is no
            // choice to offer there. Only the desktop, where a tun needs a
            // capability the app has to be granted, has a second mode worth
            // having — and it starts on the one that needs no grant at all.
            if (!Platform.isAndroid)
              SettingRow(
                icon: Icons.swap_horiz_outlined,
                title: l10n.settingsProxyMode,
                subtitle: proxyModeLabel(l10n, settings.proxyMode),
                trailing: _ModeMenu(state: state),
              ),
            // Everything below describes the `tun` inbound, which system-proxy
            // mode does not render. Hidden rather than shown doing nothing —
            // and shown on Android regardless, which always renders one.
            if (Platform.isAndroid || settings.proxyMode == ProxyMode.tun) ...[
              SettingRow(
                icon: Icons.vpn_lock_outlined,
                title: l10n.settingsTunStack,
                subtitle: settings.tunStack.label,
                trailing: _StackMenu(state: state),
              ),
              // MTU lives here rather than under Network: it is a `tun` field in
              // the generated config, same as the stack and strict route.
              SettingRow(
                icon: Icons.straighten_outlined,
                title: l10n.settingsMtu,
                subtitle: '${settings.mtu}',
                onTap: () => _editMtu(context),
              ),
              SettingRow(
                icon: Icons.alt_route_outlined,
                title: l10n.settingsStrictRoute,
                subtitle: l10n.settingsStrictRouteBody,
                value: settings.strictRoute,
                onChanged: (value) =>
                    state.applySettings(settings.copyWith(strictRoute: value)),
              ),
              SettingRow(
                icon: Icons.shield_outlined,
                title: l10n.settingsSystemProxy,
                subtitle: l10n.settingsSystemProxyBody,
                value: settings.systemProxy,
                onChanged: (value) =>
                    state.applySettings(settings.copyWith(systemProxy: value)),
              ),
              // Android can exclude selected packages at the VpnService layer.
              // Desktop system proxies have no equivalent package boundary, so
              // this control intentionally remains Android-only.
              if (Platform.isAndroid) ...[
                SettingRow(
                  icon: Icons.apps_outlined,
                  title: l10n.settingsPerAppProxy,
                  subtitle: l10n.settingsPerAppProxyBody,
                  value: settings.perAppProxyEnabled,
                  onChanged: (value) => state.applySettings(
                    settings.copyWith(perAppProxyEnabled: value),
                  ),
                ),
                if (settings.perAppProxyEnabled)
                  SettingRow(
                    icon: Icons.list_alt_outlined,
                    title: l10n.settingsPerAppProxyApps,
                    subtitle: l10n.settingsPerAppProxyAppsBody(
                      settings.perAppProxyBypass.length,
                    ),
                    onTap: () => _editPerAppProxy(context),
                  ),
              ],
            ],
          ],
        ),
        // Between Proxy and Network: the rule-sets decide *where* a packet goes,
        // which is one step above how its name was resolved.
        SettingGroup(
          title: l10n.settingsRouting,
          rows: [_RuleSetsRow(state: state)],
        ),
        SettingGroup(
          title: l10n.settingsNetwork,
          rows: [
            SettingRow(
              icon: Icons.dns_outlined,
              title: l10n.settingsRemoteDns,
              subtitle: settings.dnsRemote,
              onTap: () => _editDns(context, remote: true),
            ),
            SettingRow(
              icon: Icons.home_outlined,
              title: l10n.settingsDirectDns,
              subtitle: settings.dnsDirect,
              onTap: () => _editDns(context, remote: false),
            ),
            SettingRow(
              icon: Icons.bolt_outlined,
              title: l10n.settingsFakeIp,
              subtitle: l10n.settingsFakeIpBody,
              value: settings.fakeIp,
              onChanged: (value) =>
                  state.applySettings(settings.copyWith(fakeIp: value)),
            ),
            SettingRow(
              icon: Icons.language_outlined,
              title: l10n.settingsIpv6,
              subtitle: settings.ipv6
                  ? l10n.settingsPreferIpv4
                  : l10n.settingsIpv4Only,
              value: settings.ipv6,
              onChanged: (value) =>
                  state.applySettings(settings.copyWith(ipv6: value)),
            ),
          ],
        ),
        SettingGroup(
          title: l10n.settingsAppearance,
          rows: [
            SettingRow(
              icon: Icons.contrast_outlined,
              title: l10n.settingsTheme,
              subtitle: switch (settings.themeMode) {
                AppThemeMode.system => l10n.settingsThemeSystem,
                AppThemeMode.light => l10n.settingsThemeLight,
                AppThemeMode.dark => l10n.settingsThemeDark,
              },
              trailing: _ThemeMenu(state: state),
            ),
            SettingRow(
              icon: Icons.translate_outlined,
              title: l10n.settingsLanguage,
              subtitle: switch (settings.language) {
                AppLanguage.system => l10n.settingsLanguageSystem,
                // Endonyms: a language is named in its own language, in any UI.
                AppLanguage.english => 'English',
                AppLanguage.chinese => '中文',
              },
              trailing: _LanguageMenu(state: state),
            ),
            // Desktop only: Android has no window to close and no tray to close
            // it to — the tunnel there belongs to a foreground service.
            if (!Platform.isAndroid)
              SettingRow(
                icon: Icons.dock_outlined,
                title: l10n.settingsCloseToTray,
                subtitle: l10n.settingsCloseToTrayBody,
                value: settings.closeToTray,
                onChanged: (value) =>
                    state.applySettings(settings.copyWith(closeToTray: value)),
              ),
          ],
        ),
        SettingGroup(
          title: l10n.settingsDiagnostics,
          rows: [
            SettingRow(
              icon: Icons.receipt_long_outlined,
              title: l10n.settingsRuntimeLogs,
              subtitle: l10n.settingsEntriesBuffered(state.logs.length),
              onTap: onOpenLogs,
            ),
            SettingRow(
              icon: Icons.data_object_outlined,
              title: l10n.settingsGeneratedConfig,
              subtitle: l10n.settingsGeneratedConfigBody,
              onTap: () => _showConfig(context),
            ),
            SettingRow(
              icon: Icons.tune_outlined,
              title: l10n.settingsLogLevel,
              subtitle: settings.logLevel.name,
              trailing: _LogLevelMenu(state: state),
            ),
          ],
        ),
        SettingGroup(
          title: l10n.settingsAbout,
          rows: [
            SettingRow(
              icon: Icons.info_outline,
              title: l10n.settingsAppVersion,
              subtitle: appVersion,
            ),
            SettingRow(
              icon: Icons.inventory_2_outlined,
              title: l10n.settingsCore,
              subtitle: state.coreVersion ?? l10n.settingsChecking,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editDns(BuildContext context, {required bool remote}) async {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final settings = state.settings;
    final controller = TextEditingController(
      text: remote ? settings.dnsRemote : settings.dnsDirect,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(remote ? l10n.settingsRemoteDns : l10n.settingsDirectDns),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              style: monoStyle(size: 13, color: palette.text),
              decoration: const InputDecoration(
                hintText: 'https://1.1.1.1/dns-query',
              ),
            ),
            const SizedBox(height: Gap.md),
            Text(
              l10n.settingsDnsHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    await state.applySettings(
      remote
          ? state.settings.copyWith(dnsRemote: value)
          : state.settings.copyWith(dnsDirect: value),
    );
  }

  Future<void> _editPerAppProxy(BuildContext context) async {
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .88,
        minChildSize: .65,
        maxChildSize: .96,
        builder: (context, scrollController) => _PerAppProxySheet(
          scrollController: scrollController,
          initialSelection: state.settings.perAppProxyBypass,
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await state.applySettings(
      state.settings.copyWith(perAppProxyBypass: selected),
    );
  }

  Future<void> _editMtu(BuildContext context) async {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final controller = TextEditingController(text: '${state.settings.mtu}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsMtu),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: monoStyle(size: 13, color: palette.text),
          decoration: const InputDecoration(hintText: '9000'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
    // Below 1280 breaks common TLS handshakes; above 9000 exceeds what the
    // Android tun accepts.
    if (value == null || value < 1280 || value > 9000) return;
    await state.applySettings(state.settings.copyWith(mtu: value));
  }

  Future<void> _showConfig(BuildContext context) async {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final config = state.previewConfig();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        maxChildSize: .95,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.md, Gap.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsGeneratedConfig,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.actionCopy,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: config));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.settingsConfigCopied)),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 15, color: palette.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.settingsContainsCredentials,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: palette.amber),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xxl),
                // Selectable and copyable, but deliberately not editable: the
                // config is generated, so an editor here would invite changes
                // the next render would silently discard.
                child: SelectableText.rich(
                  TextSpan(
                    style: monoStyle(size: 11, color: palette.text),
                    children: highlightJson(config, palette),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerAppProxySheet extends StatefulWidget {
  const _PerAppProxySheet({
    required this.scrollController,
    required this.initialSelection,
  });

  final ScrollController scrollController;
  final List<String> initialSelection;

  @override
  State<_PerAppProxySheet> createState() => _PerAppProxySheetState();
}

class _PerAppProxySheetState extends State<_PerAppProxySheet> {
  late Future<List<InstalledApp>> _apps;
  late final Set<String> _selected;
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelection};
    _apps = installedApps();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (_query == query || !mounted) return;
    setState(() => _query = query);
  }

  void _retry() {
    setState(() => _apps = installedApps());
  }

  void _save() {
    Navigator.of(context).pop(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: motionOf(context, Motion.fast),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.sm, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.settingsPerAppProxyApps,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: Gap.xs),
                        Text(
                          l10n.settingsPerAppProxyBody,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.actionCancel,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.sm),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: palette.muted),
                  hintText: l10n.settingsPerAppProxySearch,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<InstalledApp>>(
                future: _apps,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Gap.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: palette.amber),
                            const SizedBox(height: Gap.sm),
                            Text(
                              l10n.settingsPerAppProxyLoadFailed,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: Gap.sm),
                            TextButton(
                              onPressed: _retry,
                              child: Text(l10n.actionRefresh),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final query = _query.trim().toLowerCase();
                  final apps = (snapshot.data ?? const <InstalledApp>[])
                      .where(
                        (app) =>
                            query.isEmpty ||
                            app.label.toLowerCase().contains(query) ||
                            app.packageName.toLowerCase().contains(query),
                      )
                      .toList();
                  if (apps.isEmpty) {
                    return Center(
                      child: Text(
                        query.isEmpty
                            ? l10n.settingsPerAppProxyNoApps
                            : l10n.settingsPerAppProxyNoMatches,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: widget.scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      Gap.lg,
                      Gap.sm,
                      Gap.lg,
                      Gap.md,
                    ),
                    itemCount: apps.length,
                    separatorBuilder: (_, __) => const Divider(indent: 52),
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return CheckboxListTile(
                        value: _selected.contains(app.packageName),
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(app.packageName);
                          } else {
                            _selected.remove(app.packageName);
                          }
                        }),
                        secondary: Icon(
                          Icons.apps_outlined,
                          color: palette.violetSoft,
                        ),
                        title: Text(
                          app.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          app.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.muted, fontSize: 11),
                        ),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsPerAppProxyAppsBody(_selected.length),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.actionCancel),
                  ),
                  const SizedBox(width: Gap.sm),
                  FilledButton(
                    onPressed: _save,
                    child: Text(l10n.actionSave),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.state, required this.subscription});

  final AppState state;
  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final refreshing = state.isRefreshing(subscription.id);
    final subtitle = switch (subscription) {
      Subscription(:final SubscriptionFailure lastFailure) =>
        subscriptionFailureText(
          l10n,
          lastFailure,
          status: subscription.lastFailureStatus,
        ),
      final item when item.isRemote => item.redactedUrl,
      _ => l10n.nodesCountLabel(subscription.nodeCount),
    };

    return SettingRow(
      icon: subscription.isRemote
          ? Icons.cloud_outlined
          : Icons.description_outlined,
      title: subscription.name,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subscription.isRemote)
            IconButton(
              tooltip: l10n.actionRefresh,
              onPressed: refreshing
                  ? null
                  : () => state.refreshSubscription(subscription.id),
              icon: refreshing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
            ),
          IconButton(
            tooltip: l10n.actionRemove,
            onPressed: () => _confirmRemove(context),
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsRemoveSubscription(subscription.name)),
        content: Text(
          l10n.settingsRemoveSubscriptionBody(subscription.nodeCount),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionRemove),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.removeSubscription(subscription.id);
    }
  }
}

class _RuleSetsRow extends StatelessWidget {
  const _RuleSetsRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final install = state.ruleSetInstall;
    final updating = state.isUpdatingRuleSets;

    final String subtitle;
    if (!state.hasLocalRuleSets) {
      // Nothing was unpacked here, so there is no file to replace: the engine
      // fetches the lists itself at start on this platform.
      subtitle = l10n.settingsRuleSetsRemote;
    } else if (install != null && install.downloaded) {
      subtitle =
          l10n.settingsRuleSetsDownloaded(relativeTime(l10n, install.at));
    } else {
      // A bundled install's timestamp is when the app first ran, not when the
      // list was compiled, so showing an age here would invent freshness.
      subtitle = l10n.settingsRuleSetsBundled;
    }

    return SettingRow(
      icon: Icons.rule_folder_outlined,
      title: l10n.settingsRuleSets,
      subtitle: subtitle,
      trailing: IconButton(
        tooltip: l10n.actionUpdate,
        // Disabled where there is nothing on disk to update.
        onPressed: updating || !state.hasLocalRuleSets
            ? null
            : () => state.updateRuleSets(),
        icon: updating
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 18),
      ),
    );
  }
}

class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    return PopupMenuButton<AppThemeMode>(
      initialValue: state.settings.themeMode,
      color: palette.surface2,
      icon: Icon(Icons.expand_more, size: 20, color: palette.muted),
      onSelected: (value) =>
          state.applySettings(state.settings.copyWith(themeMode: value)),
      itemBuilder: (context) => [
        for (final value in AppThemeMode.values)
          PopupMenuItem(
            value: value,
            child: Text(switch (value) {
              AppThemeMode.system => l10n.settingsThemeSystem,
              AppThemeMode.light => l10n.settingsThemeLight,
              AppThemeMode.dark => l10n.settingsThemeDark,
            }),
          ),
      ],
    );
  }
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    return PopupMenuButton<AppLanguage>(
      initialValue: state.settings.language,
      color: palette.surface2,
      icon: Icon(Icons.expand_more, size: 20, color: palette.muted),
      onSelected: (value) =>
          state.applySettings(state.settings.copyWith(language: value)),
      itemBuilder: (context) => [
        for (final value in AppLanguage.values)
          PopupMenuItem(
            value: value,
            child: Text(switch (value) {
              AppLanguage.system => l10n.settingsLanguageSystem,
              AppLanguage.english => 'English',
              AppLanguage.chinese => '中文',
            }),
          ),
      ],
    );
  }
}

/// What a mode is called on screen.
///
/// [TunStack] carries its own `label` because "gvisor" and "system" are the
/// engine's own tokens and read the same in every language. Mode names are
/// ordinary words, so they live in the arb files instead and this is the one
/// place that maps them.
String proxyModeLabel(L10n l10n, ProxyMode mode) => switch (mode) {
      ProxyMode.tun => l10n.settingsProxyModeTun,
      ProxyMode.systemProxy => l10n.settingsProxyModeSystemProxy,
    };

class _ModeMenu extends StatelessWidget {
  const _ModeMenu({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    return PopupMenuButton<ProxyMode>(
      initialValue: state.settings.proxyMode,
      color: palette.surface2,
      icon: Icon(Icons.expand_more, size: 20, color: palette.muted),
      onSelected: (value) =>
          state.applySettings(state.settings.copyWith(proxyMode: value)),
      itemBuilder: (context) => [
        for (final value in ProxyMode.values)
          PopupMenuItem(value: value, child: Text(proxyModeLabel(l10n, value))),
      ],
    );
  }
}

class _StackMenu extends StatelessWidget {
  const _StackMenu({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopupMenuButton<TunStack>(
      initialValue: state.settings.tunStack,
      color: palette.surface2,
      icon: Icon(Icons.expand_more, size: 20, color: palette.muted),
      onSelected: (value) =>
          state.applySettings(state.settings.copyWith(tunStack: value)),
      itemBuilder: (context) => [
        for (final value in TunStack.values)
          PopupMenuItem(value: value, child: Text(value.label)),
      ],
    );
  }
}

class _LogLevelMenu extends StatelessWidget {
  const _LogLevelMenu({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopupMenuButton<LogLevel>(
      initialValue: state.settings.logLevel,
      color: palette.surface2,
      icon: Icon(Icons.expand_more, size: 20, color: palette.muted),
      onSelected: (value) =>
          state.applySettings(state.settings.copyWith(logLevel: value)),
      itemBuilder: (context) => [
        for (final value in LogLevel.values)
          PopupMenuItem(value: value, child: Text(value.name)),
      ],
    );
  }
}
