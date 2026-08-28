/// Rules screen: routing mode plus the rule groups the config renders.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class RulesPage extends StatelessWidget {
  const RulesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = state.settings;
    final ruleMode = settings.routingMode == RoutingMode.rule;

    return PageFrame(
      title: l10n.rulesTitle,
      subtitle: l10n.rulesHowRouted,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PanelTitle(title: l10n.rulesRoutingMode, icon: Icons.alt_route),
              const SizedBox(height: Gap.lg),
              SegmentedChoice<RoutingMode>(
                values: RoutingMode.values,
                selected: settings.routingMode,
                labelOf: (value) => switch (value) {
                  RoutingMode.global => l10n.rulesModeGlobal,
                  RoutingMode.rule => l10n.rulesModeRule,
                  RoutingMode.direct => l10n.rulesModeDirect,
                },
                onChanged: (value) => state.applySettings(
                  settings.copyWith(routingMode: value),
                ),
              ),
              const SizedBox(height: Gap.md),
              Text(
                switch (settings.routingMode) {
                  RoutingMode.global => l10n.rulesModeGlobalBody,
                  RoutingMode.rule => l10n.rulesModeRuleBody,
                  RoutingMode.direct => l10n.rulesModeDirectBody,
                },
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SectionLabel(l10n.rulesActive),
        _RuleRow(
          icon: Icons.lan_outlined,
          title: l10n.rulesPrivateAddresses,
          detail: l10n.rulesPrivateAddressesBody,
          enabled: true,
          locked: true,
        ),
        _RuleRow(
          icon: Icons.dns_outlined,
          title: l10n.rulesDnsInterception,
          detail: l10n.rulesDnsInterceptionBody,
          enabled: true,
          locked: true,
        ),
        _RuleRow(
          icon: Icons.block_outlined,
          title: l10n.rulesAdsAndTrackers,
          detail: settings.blockAds
              ? l10n.rulesRejectedViaGeosite
              : l10n.rulesNotFiltered,
          enabled: settings.blockAds,
          onChanged: (value) =>
              state.applySettings(settings.copyWith(blockAds: value)),
        ),
        _RuleRow(
          icon: Icons.public,
          title: l10n.rulesChinaDirect,
          detail: ruleMode ? l10n.rulesChinaDirectBody : l10n.rulesOnlyInRuleMode,
          enabled: ruleMode,
          locked: true,
        ),
        const SizedBox(height: Gap.sm),
        Text(
          l10n.rulesSetsNote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.enabled,
    this.onChanged,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  /// Rules the config always emits; shown for transparency, not editable.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: enabled
                    ? palette.violet.withValues(alpha: .13)
                    : palette.surface3,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: enabled ? palette.violetSoft : palette.faint,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (locked)
              StatusPill(
                label: enabled ? l10n.rulesStateOn : l10n.rulesStateOff,
                color: enabled ? palette.mint : palette.faint,
                compact: true,
              )
            else
              Switch(value: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
