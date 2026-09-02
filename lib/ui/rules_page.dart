/// Rules screen: routing mode plus the rule groups the config renders.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/custom_rule.dart';
import '../state/app_state.dart';
import 'notice_text.dart';
import 'rule_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class RulesPage extends StatelessWidget {
  const RulesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) =>
      PageBody(state: state, builder: _build);

  Widget _build(BuildContext context) {
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
        // Above the built-in list, because that is where they are matched: the
        // config renders these first, so a rule the user typed beats the bundled
        // answer. Reading order and match order are the same thing here.
        SectionLabel(
          l10n.rulesCustom,
          trailing: IconButton(
            onPressed: () => _addRule(context, state),
            tooltip: l10n.rulesCustomAdd,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 20),
          ),
        ),
        if (state.customRules.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm),
            child: EmptyState(
              icon: Icons.rule_outlined,
              title: l10n.rulesCustomEmpty,
              message: l10n.rulesCustomEmptyBody,
              action: FilledButton.icon(
                onPressed: () => _addRule(context, state),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.rulesCustomAdd),
              ),
            ),
          )
        else ...[
          for (final (index, rule) in state.customRules.indexed)
            _CustomRuleRow(
              key: ValueKey(rule.id),
              state: state,
              rule: rule,
              index: index,
              total: state.customRules.length,
            ),
          const SizedBox(height: Gap.sm),
          Text(
            l10n.rulesCustomNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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

/// Opens the editor for a new rule, and adds it if the user saves.
///
/// The sheet does not touch state — it returns the edited rule — so the same
/// sheet serves add and edit, and this decides which it was.
Future<void> _addRule(BuildContext context, AppState state) async {
  final rule = await showRuleSheet(
    context,
    rule: state.newCustomRule(),
    isNew: true,
  );
  if (rule != null) await state.addCustomRule(rule);
}

/// One of the user's own rules.
///
/// Shows what it matches, what it does, and where it sits — the last because the
/// position decides which of two overlapping rules wins, and a list whose order
/// is invisible cannot be reasoned about.
class _CustomRuleRow extends StatelessWidget {
  const _CustomRuleRow({
    super.key,
    required this.state,
    required this.rule,
    required this.index,
    required this.total,
  });

  final AppState state;
  final CustomRule rule;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final problem = rule.problem;
    // A rule that cannot be rendered is skipped by the builder, so saying "off"
    // would be a lie about why. It reads as a problem, in amber, with the reason.
    final broken = problem != null;
    final active = rule.enabled && !broken;

    final accent = switch (rule.target) {
      RuleTarget.proxy => palette.violetSoft,
      RuleTarget.direct => palette.mint,
      RuleTarget.block => palette.danger,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Panel(
        onTap: () => _edit(context),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tintFill(broken ? palette.amber : accent),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                broken ? Icons.warning_amber_rounded : _icon(rule.matcher),
                size: 17,
                color: broken ? palette.amber : accent,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.value.isEmpty ? l10n.rulesProblemEmpty : rule.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      color: active ? palette.text : palette.faint,
                      weight: FontWeight.w600,
                      size: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    broken
                        ? ruleProblemText(l10n, problem)
                        : ruleMatcherText(l10n, rule.matcher),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: broken ? palette.amber : palette.muted,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            // Position, and the way to change it. Order is behaviour, so it is
            // shown rather than left to be inferred from the list.
            _ReorderButtons(state: state, index: index, total: total),
            const SizedBox(width: Gap.xs),
            _ActionBadge(
              label: ruleTargetText(l10n, rule.target).toUpperCase(),
              color: active ? accent : palette.faint,
            ),
            const SizedBox(width: Gap.xs),
            Switch(
              value: rule.enabled,
              // Still togglable while broken: turning a bad rule off is a
              // reasonable thing to want, and it is also how a user parks one
              // they mean to come back to.
              onChanged: (value) =>
                  state.updateCustomRule(rule.copyWith(enabled: value)),
            ),
            IconButton(
              onPressed: () => state.removeCustomRule(rule.id),
              tooltip: l10n.actionRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              color: palette.faint,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final edited = await showRuleSheet(context, rule: rule, isNew: false);
    if (edited != null) await state.updateCustomRule(edited);
  }

  static IconData _icon(RuleMatcher matcher) => switch (matcher) {
        RuleMatcher.domain => Icons.language,
        RuleMatcher.domainSuffix => Icons.account_tree_outlined,
        RuleMatcher.domainKeyword => Icons.search,
        RuleMatcher.ipCidr => Icons.router_outlined,
        RuleMatcher.port => Icons.settings_ethernet,
        RuleMatcher.processName => Icons.memory_outlined,
      };
}

/// Up and down, disabled at the ends.
///
/// Buttons rather than drag-and-drop: the list is short, these work with a
/// keyboard and a screen reader, and a drag target inside a tappable row that
/// also opens an editor is a hit-area fight.
class _ReorderButtons extends StatelessWidget {
  const _ReorderButtons({
    required this.state,
    required this.index,
    required this.total,
  });

  final AppState state;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Arrow(
          icon: Icons.keyboard_arrow_up,
          tooltip: l10n.rulesMoveUp,
          color: palette.faint,
          onPressed:
              index == 0 ? null : () => state.moveCustomRule(index, index - 1),
        ),
        _Arrow(
          icon: Icons.keyboard_arrow_down,
          tooltip: l10n.rulesMoveDown,
          color: palette.faint,
          onPressed: index == total - 1
              ? null
              : () => state.moveCustomRule(index, index + 1),
        ),
      ],
    );
  }
}

/// A 20px-tall arrow, so the pair fits one row's height.
class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 20,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: color,
        icon: Icon(icon),
      ),
    );
  }
}
