/// Settings screen: subscriptions, network behaviour, appearance, diagnostics.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/subscription.dart';
import '../state/app_state.dart';
import '../version.dart';
import 'import_sheet.dart';
import 'json_highlight.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage(
      {super.key, required this.state, required this.onOpenLogs});

  final AppState state;
  final VoidCallback onOpenLogs;

  @override
  Widget build(BuildContext context) {
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
          ],
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

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.state, required this.subscription});

  final AppState state;
  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final refreshing = state.isRefreshing(subscription.id);
    final subtitle = switch (subscription) {
      final item when item.lastError != null => item.lastError!,
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
