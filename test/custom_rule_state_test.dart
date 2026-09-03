/// Custom rules through [AppState]: persistence, order, and the reload.
///
/// The reload is the part worth pinning. The bundled rule-sets are files the
/// engine reads at start, so a download only applies at the next connect — but
/// route rules are part of the config, so a rule the user just typed only takes
/// effect if the tunnel is reloaded. Getting that wrong means the rule appears to
/// save and changes nothing until the next connect.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/models/custom_rule.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, node;

Future<({AppState state, FakeProxyController controller, Storage storage})>
    harness({List<CustomRule> rules = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  await storage.writeNodes([node('a', 'Tokyo')]);
  if (rules.isNotEmpty) await storage.writeCustomRules(rules);
  final controller = FakeProxyController();
  return (
    state: AppState(storage: storage, controller: controller),
    controller: controller,
    storage: storage,
  );
}

CustomRule rule({
  String id = 'r1',
  String value = 'example.com',
  RuleTarget target = RuleTarget.direct,
  bool enabled = true,
}) =>
    CustomRule(
      id: id,
      matcher: RuleMatcher.domainSuffix,
      value: value,
      target: target,
      enabled: enabled,
    );

void main() {
  test('a new rule is persisted and appears in order', () async {
    final h = await harness();
    addTearDown(h.state.dispose);

    await h.state.addCustomRule(rule(value: 'a.example.com'));
    await h.state.addCustomRule(rule(id: 'r2', value: 'b.example.com'));

    expect(h.state.customRules.map((r) => r.value),
        ['a.example.com', 'b.example.com']);
    // Appended, not prepended: a user adding a rule expects it after the ones
    // already there, not silently ahead of them.
    expect(h.storage.readCustomRules().map((r) => r.value),
        ['a.example.com', 'b.example.com']);
  });

  test('rules survive a restart in the same order', () async {
    // Order is behaviour, so a reload that reordered them would change routing.
    final h = await harness(rules: [
      rule(id: 'r1', value: 'first.example.com'),
      rule(id: 'r2', value: 'second.example.com'),
    ]);
    addTearDown(h.state.dispose);

    expect(h.state.customRules.map((r) => r.id), ['r1', 'r2']);
  });

  test('editing replaces in place rather than moving to the end', () async {
    final h = await harness(rules: [
      rule(id: 'r1', value: 'a.example.com'),
      rule(id: 'r2', value: 'b.example.com'),
    ]);
    addTearDown(h.state.dispose);

    await h.state.updateCustomRule(
      h.state.customRules.first.copyWith(value: 'changed.example.com'),
    );

    // Still first. Moving an edited rule would change which of two overlapping
    // rules wins, as a side effect of fixing a typo.
    expect(h.state.customRules.map((r) => r.value),
        ['changed.example.com', 'b.example.com']);
  });

  test('editing a rule that is gone does nothing', () async {
    // The sheet is async; the row behind it can be deleted while it is open.
    final h = await harness(rules: [rule(id: 'r1')]);
    addTearDown(h.state.dispose);

    await h.state.updateCustomRule(rule(id: 'vanished', value: 'x.example.com'));

    expect(h.state.customRules, hasLength(1));
    expect(h.state.customRules.single.id, 'r1');
  });

  test('removing takes only that rule', () async {
    final h = await harness(rules: [
      rule(id: 'r1'),
      rule(id: 'r2'),
      rule(id: 'r3'),
    ]);
    addTearDown(h.state.dispose);

    await h.state.removeCustomRule('r2');

    expect(h.state.customRules.map((r) => r.id), ['r1', 'r3']);
  });

  group('moving', () {
    test('changes the order and persists it', () async {
      final h = await harness(rules: [
        rule(id: 'r1'),
        rule(id: 'r2'),
        rule(id: 'r3'),
      ]);
      addTearDown(h.state.dispose);

      await h.state.moveCustomRule(2, 0);

      expect(h.state.customRules.map((r) => r.id), ['r3', 'r1', 'r2']);
      expect(h.storage.readCustomRules().map((r) => r.id),
          ['r3', 'r1', 'r2']);
    });

    test('an out-of-range or no-op move is ignored', () async {
      // The arrows are disabled at the ends, but the guard is what makes a
      // double-tap during a rebuild harmless.
      final h = await harness(rules: [rule(id: 'r1'), rule(id: 'r2')]);
      addTearDown(h.state.dispose);

      for (final (from, to) in [(-1, 0), (0, -1), (0, 5), (5, 0), (1, 1)]) {
        await h.state.moveCustomRule(from, to);
        expect(h.state.customRules.map((r) => r.id), ['r1', 'r2'],
            reason: 'move($from, $to) changed the list');
      }
    });
  });

  group('reload', () {
    test('a rule change reloads a running tunnel', () async {
      // Route rules live in the config, so this is the only way a rule the user
      // just typed takes effect now instead of at the next connect.
      final h = await harness();
      addTearDown(h.state.dispose);
      await h.state.connect();
      final before = h.controller.reloadedConfigs.length;

      await h.state.addCustomRule(rule(value: 'work.example.com'));

      expect(h.controller.reloadedConfigs, hasLength(before + 1));
      expect(h.controller.reloadedConfigs.last, contains('work.example.com'));
    });

    test('the reloaded config carries the rule as sing-box wants it', () async {
      final h = await harness();
      addTearDown(h.state.dispose);
      await h.state.connect();

      await h.state.addCustomRule(rule(target: RuleTarget.block));

      expect(h.controller.reloadedConfigs.last, contains('"action": "reject"'));
    });

    test('toggling a rule off reloads without it', () async {
      final h = await harness(rules: [rule(value: 'parked.example.com')]);
      addTearDown(h.state.dispose);
      await h.state.connect();

      await h.state.updateCustomRule(
        h.state.customRules.single.copyWith(enabled: false),
      );

      expect(
        h.controller.reloadedConfigs.last,
        isNot(contains('parked.example.com')),
      );
      // Kept in the list though: parking a rule must not mean retyping it.
      expect(h.state.customRules.single.enabled, isFalse);
    });

    test('a change while disconnected does not try to reload', () async {
      // There is no engine to reload, and reload on a dead controller would
      // surface as a notice the user cannot act on.
      final h = await harness();
      addTearDown(h.state.dispose);

      await h.state.addCustomRule(rule());

      expect(h.controller.reloadedConfigs, isEmpty);
      expect(h.state.customRules, hasLength(1));
    });
  });

  test('a corrupt payload starts clean rather than blocking launch', () async {
    SharedPreferences.setMockInitialValues({'custom_rules.v1': 'not json'});
    final storage = await Storage.open();

    expect(storage.readCustomRules(), isEmpty);
  });

  test('a record with no id is dropped, not shown as an unusable row', () async {
    // The UI keys every button on the id, so a row without one would ignore edit,
    // delete and reorder alike.
    SharedPreferences.setMockInitialValues({
      'custom_rules.v1':
          '[{"matcher":"domain","value":"a.example.com","target":"proxy"},'
              '{"id":"ok","matcher":"domain","value":"b.example.com","target":"proxy"}]',
    });
    final storage = await Storage.open();

    expect(storage.readCustomRules().map((r) => r.id), ['ok']);
  });
}
