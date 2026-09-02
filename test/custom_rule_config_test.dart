/// Custom rules as they reach the rendered config.
///
/// Position is the behaviour here. sing-box takes the first route rule that
/// matches, so where these land decides whether a rule the user typed beats the
/// bundled CN list or is shadowed by it — and that cannot be checked by reading
/// the rule in isolation.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/models/custom_rule.dart';

import 'widget_test.dart' show node;

CustomRule rule({
  String id = 'r1',
  RuleMatcher matcher = RuleMatcher.domainSuffix,
  String value = 'example.com',
  RuleTarget target = RuleTarget.direct,
  bool enabled = true,
}) =>
    CustomRule(
      id: id,
      matcher: matcher,
      value: value,
      target: target,
      enabled: enabled,
    );

/// The `route.rules` array of a config built with [rules].
List<Map<String, dynamic>> routeRules(
  List<CustomRule> rules, {
  AppSettings settings = const AppSettings(),
}) {
  final config = ConfigBuilder.build(
    nodes: [node('a', 'Tokyo')],
    selectedNodeId: 'a',
    settings: settings,
    clashSecret: 'secret',
    customRules: rules,
    ruleSetDir: '/tmp/rule-sets',
  );
  final route = config['route'] as Map<String, dynamic>;
  return (route['rules'] as List).cast<Map<String, dynamic>>();
}

/// Index of the first rule matching [test], or -1.
int indexWhere(
  List<Map<String, dynamic>> rules,
  bool Function(Map<String, dynamic> rule) test,
) =>
    rules.indexWhere(test);

void main() {
  group('rendering', () {
    test('a domain suffix rule becomes the sing-box field and outbound', () {
      final rules = routeRules([rule()]);
      final mine = rules.firstWhere((r) => r.containsKey('domain_suffix'));

      expect(mine['domain_suffix'], ['example.com']);
      expect(mine['outbound'], ConfigTags.direct);
    });

    test('block renders as an action, not an outbound', () {
      // reject is an action in sing-box's schema; naming it as an outbound would
      // be a tag that does not exist and the tunnel would not start.
      final rules = routeRules([rule(target: RuleTarget.block)]);
      final mine = rules.firstWhere((r) => r.containsKey('domain_suffix'));

      expect(mine['action'], 'reject');
      expect(mine.containsKey('outbound'), isFalse);
    });

    test('proxy renders the selector tag', () {
      final rules = routeRules([rule(target: RuleTarget.proxy)]);
      final mine = rules.firstWhere((r) => r.containsKey('domain_suffix'));

      expect(mine['outbound'], ConfigTags.proxy);
    });

    test('a port renders as a number, because the schema says uint16', () {
      // The one type that is not a string. Quoted, sing-box fails at decode with
      // "cannot unmarshal string into Go value of type uint16" and the whole
      // tunnel refuses to start over one rule.
      final rules = routeRules([rule(matcher: RuleMatcher.port, value: '443')]);
      final mine = rules.firstWhere((r) => r.containsKey('port'));

      expect(mine['port'], [443]);
      expect(mine['port'].first, isA<int>());
    });

    test('every matcher renders under its own sing-box key', () {
      for (final matcher in RuleMatcher.values) {
        final value = switch (matcher) {
          RuleMatcher.port => '443',
          RuleMatcher.ipCidr => '10.0.0.0/8',
          _ => 'example.com',
        };
        final rules = routeRules([rule(matcher: matcher, value: value)]);

        expect(
          rules.any((r) => r.containsKey(matcher.field)),
          isTrue,
          reason: '${matcher.name} did not render as ${matcher.field}',
        );
      }
    });
  });

  group('order', () {
    test('custom rules come before the bundled CN list', () {
      // The whole point. Below it, a user's rule for one .cn domain would never
      // be reached — the list would have claimed it first.
      final rules = routeRules(
        [rule(value: 'work.cn', target: RuleTarget.proxy)],
        settings: const AppSettings(routingMode: RoutingMode.rule),
      );

      final mine = indexWhere(rules, (r) => r.containsKey('domain_suffix'));
      final cn = indexWhere(
        rules,
        (r) => (r['rule_set'] as List?)?.contains('geosite-cn') ?? false,
      );

      expect(mine, greaterThanOrEqualTo(0));
      expect(cn, greaterThanOrEqualTo(0));
      expect(mine, lessThan(cn), reason: 'shadowed by the CN list');
    });

    test('custom rules come before the ad list', () {
      // So a user can un-block something the ad list rejects.
      final rules = routeRules(
        [rule(value: 'ads.example.com', target: RuleTarget.proxy)],
        settings: const AppSettings(blockAds: true),
      );

      final mine = indexWhere(rules, (r) => r.containsKey('domain_suffix'));
      final ads = indexWhere(
        rules,
        (r) => (r['rule_set'] as List?)?.contains('geosite-ads') ?? false,
      );

      expect(mine, lessThan(ads));
    });

    test('custom rules come after the clash-mode overrides', () {
      // Those are a global switch the user just flipped, not an opinion about a
      // destination — they have to win over everything.
      final rules = routeRules([rule()]);

      final global = indexWhere(rules, (r) => r['clash_mode'] == 'Global');
      final mine = indexWhere(rules, (r) => r.containsKey('domain_suffix'));

      expect(global, lessThan(mine));
    });

    test('custom rules come after the LAN bypass', () {
      // Local traffic stays off the tunnel regardless; a custom rule for a
      // private range would otherwise be able to send the LAN through it.
      final rules = routeRules(
        [rule()],
        settings: const AppSettings(bypassLan: true),
      );

      final lan = indexWhere(rules, (r) => r['ip_is_private'] == true);
      final mine = indexWhere(rules, (r) => r.containsKey('domain_suffix'));

      expect(lan, lessThan(mine));
    });

    test('the user order is the config order', () {
      // First match wins, so the order on screen has to be the order rendered —
      // otherwise two overlapping rules resolve differently than the list reads.
      final rules = routeRules([
        rule(id: 'a', value: 'first.example.com'),
        rule(id: 'b', value: 'second.example.com'),
        rule(id: 'c', value: 'third.example.com'),
      ]);

      final mine = rules
          .where((r) => r.containsKey('domain_suffix'))
          .map((r) => (r['domain_suffix'] as List).first)
          .toList();

      expect(mine, [
        'first.example.com',
        'second.example.com',
        'third.example.com',
      ]);
    });
  });

  group('skipping', () {
    test('a disabled rule is not rendered', () {
      final rules = routeRules([rule(enabled: false)]);

      expect(rules.any((r) => r.containsKey('domain_suffix')), isFalse);
    });

    test('an invalid rule is not rendered, so it cannot stop the tunnel', () {
      // The reason validation exists at all. A malformed route rule makes
      // sing-box refuse to start, and the user would have no way to tell which
      // line did it.
      final rules = routeRules([
        rule(matcher: RuleMatcher.port, value: 'not-a-port'),
        rule(matcher: RuleMatcher.ipCidr, value: '10.0.0.256'),
        rule(value: ''),
      ]);

      expect(rules.any((r) => r.containsKey('port')), isFalse);
      expect(rules.any((r) => r.containsKey('ip_cidr')), isFalse);
      expect(rules.any((r) => r.containsKey('domain_suffix')), isFalse);
    });

    test('a valid rule still renders alongside an invalid one', () {
      // One bad line must not cost the user the rest of their list.
      final rules = routeRules([
        rule(id: 'bad', matcher: RuleMatcher.port, value: 'nope'),
        rule(id: 'good', value: 'example.com'),
      ]);

      expect(rules.any((r) => r.containsKey('domain_suffix')), isTrue);
    });

    test('no rules leaves the config as it was', () {
      // Rendering an empty array or a stray key would change a config that
      // thousands of connections already work against.
      final without = jsonEncode(routeRules(const []));
      final withDisabled = jsonEncode(routeRules([rule(enabled: false)]));

      expect(withDisabled, without);
    });
  });
}
