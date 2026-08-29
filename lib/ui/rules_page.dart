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
        // Each badge names the action the generated config actually takes for
        // that rule, so the page stays honest against config_builder.dart.
        _RuleRow(
          icon: Icons.lan_outlined,
          title: l10n.rulesPrivateAddresses,
          detail: l10n.rulesPrivateAddressesBody,
          action: _RuleAction.direct,
          enabled: true,
          locked: true,
        ),
        _RuleRow(
          icon: Icons.dns_outlined,
          title: l10n.rulesDnsInterception,
          detail: l10n.rulesDnsInterceptionBody,
          action: _RuleAction.dns,
          enabled: true,
          locked: true,
        ),
        _RuleRow(
          icon: Icons.block_outlined,
          title: l10n.rulesAdsAndTrackers,
          detail: settings.blockAds
              ? l10n.rulesRejectedViaGeosite
              : l10n.rulesNotFiltered,
          action: _RuleAction.block,
          enabled: settings.blockAds,
          onChanged: (value) =>
              state.applySettings(settings.copyWith(blockAds: value)),
        ),
        _RuleRow(
          icon: Icons.public,
          title: l10n.rulesChinaDirect,
          detail:
              ruleMode ? l10n.rulesChinaDirectBody : l10n.rulesOnlyInRuleMode,
          action: _RuleAction.direct,
          enabled: ruleMode,
          locked: true,
        ),
        // The builder's `final` outbound: whatever no rule above matched. It is
        // the only row that can read PROXY, and it follows the mode directly —
        // global and rule both end at the proxy, direct does not.
        _RuleRow(
          icon: Icons.call_split,
          title: l10n.rulesFallback,
          detail: settings.routingMode == RoutingMode.direct
              ? l10n.rulesFallbackDirect
              : l10n.rulesFallbackProxy,
          action: settings.routingMode == RoutingMode.direct
              ? _RuleAction.direct
              : _RuleAction.proxy,
          enabled: true,
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

/// What the generated config does with traffic a rule matches.
///
/// These mirror `config_builder.dart`: `outbound: direct`, `outbound: proxy`,
/// `action: reject` and `action: hijack-dns`. [dns] is not one of the routing
/// verbs — a hijacked query is answered locally rather than routed — so it gets
/// its own badge instead of being flattened into direct or proxy.
enum _RuleAction { direct, proxy, block, dns }

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.enabled,
    this.onChanged,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final _RuleAction action;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  /// Rules the config always emits; shown for transparency, not editable.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;

    final (badge, badgeColor) = switch (action) {
      _RuleAction.direct => (l10n.rulesBadgeDirect, palette.mint),
      _RuleAction.proxy => (l10n.rulesBadgeProxy, palette.violetSoft),
      _RuleAction.block => (l10n.rulesBadgeBlock, palette.danger),
      _RuleAction.dns => (l10n.rulesBadgeDns, palette.sky),
    };

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
                borderRadius: BorderRadius.circular(AppRadius.sm),
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
            // The badge carries the state as well as the action: dimmed means
            // the rule is not in the config right now. Colour alone would not
            // say that, so the state is spelled out for screen readers.
            Semantics(
              label:
                  '$badge · ${enabled ? l10n.rulesStateOn : l10n.rulesStateOff}',
              child: _ActionBadge(
                label: badge,
                color: enabled ? badgeColor : palette.faint,
              ),
            ),
            if (!locked) ...[
              const SizedBox(width: Gap.sm),
              Switch(value: enabled, onChanged: onChanged),
            ],
          ],
        ),
      ),
    );
  }
}

/// Uppercase routing verb, drawn in the mono face so it reads as the config
/// keyword it comes from rather than as prose.
class _ActionBadge extends StatelessWidget {
  const _ActionBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 5),
      decoration: BoxDecoration(
        color: tintFill(color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Text(
        label,
        style: monoStyle(color: color, size: 10, weight: FontWeight.w600),
      ),
    );
  }
}
