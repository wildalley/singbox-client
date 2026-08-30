/// Handing the choice of exit to the engine.
///
/// "Auto" is not a node, so it cannot live in the node list: it is stored as a
/// sentinel in the same key a node id would occupy, and the whole point of that
/// shape is that nothing downstream needs a second code path. These tests hold
/// that line — the sentinel never leaks out as a node, the config still names the
/// `urltest` group, and the paths that clear a selection do not mistake the
/// sentinel for a stale id.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, buildState, node;

/// The `proxy` selector out of a rendered config.
Map<String, dynamic> _selector(String configJson) {
  final outbounds = (jsonDecode(configJson) as Map)['outbounds'] as List;
  return outbounds.cast<Map<String, dynamic>>().firstWhere(
        (outbound) => outbound['tag'] == ConfigTags.proxy,
      );
}

void main() {
  group('state', () {
    test('auto is a selection, not a node', () async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);
      final state = harness.state;

      await state.selectAuto();

      expect(state.isAutoSelected, isTrue);
      expect(state.selectedNodeId, AppState.autoSelection);
      expect(state.selectedNode, isNull,
          reason: 'no node backs it, and every reader already handles null');
    });

    test('auto survives a restart', () async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);
      await harness.state.selectAuto();

      // Same preferences, a second AppState over them. The constructor is what
      // reads storage, so building one is the restart.
      final reopened = AppState(
        storage: Storage(await SharedPreferences.getInstance()),
        controller: FakeProxyController(),
      );
      addTearDown(reopened.dispose);

      expect(reopened.isAutoSelected, isTrue,
          reason: 'a fresh read must not mistake the sentinel for a missing '
              'node and fall back to the first one');
    });

    test('auto needs something to choose between', () async {
      final harness = await buildState();
      addTearDown(harness.state.dispose);

      await harness.state.selectAuto();

      expect(harness.state.isAutoSelected, isFalse,
          reason: 'with no nodes the config selector falls back to direct, so '
              'reporting auto would name a group that is not there');
    });

    test('picking a node again leaves auto behind', () async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);
      final state = harness.state;

      await state.selectAuto();
      await state.selectNode(state.nodes.single);

      expect(state.isAutoSelected, isFalse);
      expect(state.selectedNode?.name, 'Tokyo');
    });
  });

  group('config', () {
    test('auto makes the urltest group the selector default', () async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo'), node('b', 'Osaka')],
      );
      addTearDown(harness.state.dispose);

      await harness.state.selectAuto();
      final selector = _selector(harness.state.previewConfig());

      expect(selector['default'], ConfigTags.auto);
      expect(selector['outbounds'], contains(ConfigTags.auto),
          reason: 'the default has to be one of the members');
    });

    test('the sentinel never reaches the config as a tag', () async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);

      await harness.state.selectAuto();

      expect(harness.state.previewConfig(),
          isNot(contains(AppState.autoSelection)),
          reason: 'it is a storage key value, not part of the config vocabulary');
    });
  });

  group('live switch', () {
    testWidgets('choosing auto while connected moves the selector',
        (tester) async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo'), node('b', 'Osaka')],
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      await harness.state.selectAuto();

      expect(harness.controller.selectedOutbounds, [ConfigTags.auto],
          reason: 'the group is a member of the selector, so the engine can be '
              'pointed at it without a restart');
      expect(harness.controller.stopCount, 0);
    });
  });

  group('the row', () {
    testWidgets('tapping it selects auto', (tester) async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.hub_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();

      expect(harness.state.isAutoSelected, isTrue);
    });

    testWidgets('the home page names auto as the exit', (tester) async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);
      await harness.state.selectAuto();

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();

      expect(find.text('Auto'), findsWidgets);
      expect(find.text('No node selected'), findsNothing,
          reason: 'auto reaches the cards as a null node, but it is a choice '
              'the user made');
    });

    testWidgets('a search hides it', (tester) async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.hub_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Tok');
      await tester.pumpAndSettle();

      expect(find.text('Auto'), findsNothing,
          reason: 'it matches no query, so leaving it above the results would '
              'read as one of them');
      expect(find.text('Tokyo'), findsOneWidget);
    });
  });

  group('removal', () {
    test('removing a node leaves auto alone while others remain', () async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo'), node('b', 'Osaka')],
      );
      addTearDown(harness.state.dispose);
      final state = harness.state;

      await state.selectAuto();
      await state.removeNode('a');

      expect(state.isAutoSelected, isTrue,
          reason: 'auto names no node, so losing one cannot invalidate it');
    });

    test('the last node going clears auto', () async {
      final harness = await buildState(nodes: [node('a', 'Tokyo')]);
      addTearDown(harness.state.dispose);
      final state = harness.state;

      await state.selectAuto();
      await state.removeNode('a');

      expect(state.selectedNodeId, isNull,
          reason: 'the sentinel would outlive the reason it was set');
    });
  });
}
