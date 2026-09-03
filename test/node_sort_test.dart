/// Ordering the node list by measured latency.
///
/// The sort is a view preference, and these tests hold the three things that
/// makes it: it never reorders across sources, the two states with no figure
/// (untested, unreachable) end up behind every real one rather than at the top,
/// and choosing it does not reach the tunnel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/models/node_sort.dart';
import 'package:singbox_client/models/subscription.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, buildState, node;

/// [node] with a latency: the shared helper builds untested ones.
ProxyNode measured(String id, String name, int? latencyMs) =>
    node(id, name).copyWith(latencyMs: latencyMs);

/// Node names in the order their rows are laid out on screen.
///
/// Read from the rendered geometry rather than from the widget list, because the
/// question is what the user sees from top to bottom.
List<String> renderedOrder(WidgetTester tester, List<String> names) {
  final placed = <(double, String)>[];
  for (final name in names) {
    final finder = find.text(name);
    if (finder.evaluate().isEmpty) continue;
    placed.add((tester.getTopLeft(finder).dy, name));
  }
  placed.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final entry in placed) entry.$2];
}

Future<void> openNodes(WidgetTester tester, AppState state) async {
  // The page is a lazy sliver list, so rows below the viewport are never built
  // and an order assertion would only see the top of it.
  tester.view
    ..physicalSize = const Size(800, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(SingBoxApp(state: state));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.hub_outlined));
  await tester.pumpAndSettle();
}

void main() {
  group('sortNodes', () {
    test('source order is left exactly as it came', () {
      final nodes = [
        measured('a', 'Alpha', 300),
        measured('b', 'Bravo', 40),
        measured('c', 'Charlie', null),
      ];
      expect(
        [for (final item in sortNodes(nodes, NodeSort.source)) item.id],
        ['a', 'b', 'c'],
      );
    });

    test('latency order puts the fastest first', () {
      final nodes = [
        measured('a', 'Alpha', 300),
        measured('b', 'Bravo', 40),
        measured('c', 'Charlie', 120),
      ];
      expect(
        [for (final item in sortNodes(nodes, NodeSort.latency)) item.id],
        ['b', 'c', 'a'],
      );
    });

    test('untested sits behind every measured node', () {
      final nodes = [
        measured('a', 'Alpha', null),
        measured('b', 'Bravo', 900),
      ];
      expect(
        [for (final item in sortNodes(nodes, NodeSort.latency)) item.id],
        ['b', 'a'],
      );
    });

    test('unreachable sits behind untested', () {
      // A failed probe is an answer, no probe is an open question — so the node
      // that is known not to work goes last.
      final nodes = [
        measured('a', 'Alpha', ProxyNode.unreachableLatency),
        measured('b', 'Bravo', null),
        measured('c', 'Charlie', 80),
      ];
      expect(
        [for (final item in sortNodes(nodes, NodeSort.latency)) item.id],
        ['c', 'b', 'a'],
      );
    });

    test('equal latencies keep their source order', () {
      // `List.sort` is not stable, so this is the index tiebreak: without it two
      // nodes measured at the same millisecond could swap between builds.
      final nodes = [
        for (var i = 0; i < 12; i++) measured('n$i', 'Node $i', 100),
      ];
      expect(
        [for (final item in sortNodes(nodes, NodeSort.latency)) item.id],
        [for (var i = 0; i < 12; i++) 'n$i'],
      );
    });

    test('the argument list is not touched', () {
      final nodes = [measured('a', 'Alpha', 300), measured('b', 'Bravo', 40)];
      sortNodes(nodes, NodeSort.latency);
      expect([for (final item in nodes) item.id], ['a', 'b']);
    });
  });

  group('persistence', () {
    test('source order is the default', () async {
      final built = await buildState();
      expect(built.state.nodeSort, NodeSort.source);
    });

    test('the choice survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final first = AppState(storage: storage, controller: FakeProxyController());
      await first.setNodeSort(NodeSort.latency);

      // A second state over the same store, which is what a restart is: the
      // constructor reads storage, so there is nothing to await.
      final reopened =
          AppState(storage: storage, controller: FakeProxyController());
      expect(reopened.nodeSort, NodeSort.latency);
    });

    test('an unknown stored value falls back to source order', () async {
      SharedPreferences.setMockInitialValues({'node_sort.v1': 'by_vibes'});
      final storage = await Storage.open();
      expect(storage.readNodeSort(), NodeSort.source);
    });

    test('switching sort never reloads the tunnel', () async {
      // The reason this lives outside AppSettings: `applySettings` restarts a
      // running config, and a sort order is not worth the connections.
      final built = await buildState(nodes: [node('a', 'Alpha')]);
      await built.state.setNodeSort(NodeSort.latency);
      // Both lists: nothing started, and nothing was handed new routing either.
      // Before the fake kept them apart, reload landed in startedConfigs and
      // this assertion could not tell the two apart.
      expect(built.controller.startedConfigs, isEmpty);
      expect(built.controller.reloadedConfigs, isEmpty);
      expect(built.controller.stopCount, 0);
    });
  });

  group('the page', () {
    testWidgets('the header button reorders the rows', (tester) async {
      final built = await buildState(nodes: [
        measured('a', 'Alpha', 300),
        measured('b', 'Bravo', 40),
        measured('c', 'Charlie', 120),
      ]);
      await openNodes(tester, built.state);

      const names = ['Alpha', 'Bravo', 'Charlie'];
      expect(renderedOrder(tester, names), names);

      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pumpAndSettle();

      expect(renderedOrder(tester, names), ['Bravo', 'Charlie', 'Alpha']);
      expect(built.state.nodeSort, NodeSort.latency);
    });

    testWidgets('tapping it again restores source order', (tester) async {
      final built = await buildState(nodes: [
        measured('a', 'Alpha', 300),
        measured('b', 'Bravo', 40),
      ]);
      await openNodes(tester, built.state);

      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pumpAndSettle();

      expect(renderedOrder(tester, ['Alpha', 'Bravo']), ['Alpha', 'Bravo']);
      expect(built.state.nodeSort, NodeSort.source);
    });

    testWidgets('the order stays inside each source', (tester) async {
      // The sections are the user's own grouping. A global order would have to
      // dissolve them to mean anything, so a fast node in the second source
      // never climbs above the first source's rows.
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      await storage.writeSubscriptions([
        Subscription(
          id: 's1',
          name: 'Alpha Source',
          kind: SubscriptionKind.remote,
          url: 'https://s1.example.com/sub',
          nodeCount: 2,
        ),
        Subscription(
          id: 's2',
          name: 'Beta Source',
          kind: SubscriptionKind.remote,
          url: 'https://s2.example.com/sub',
          nodeCount: 2,
        ),
      ]);
      await storage.writeNodes([
        measured('a', 'Alpha Slow', 400).copyWith(subscriptionId: 's1'),
        measured('b', 'Alpha Quick', 300).copyWith(subscriptionId: 's1'),
        measured('c', 'Beta Slow', 90).copyWith(subscriptionId: 's2'),
        measured('d', 'Beta Quick', 20).copyWith(subscriptionId: 's2'),
      ]);
      final state =
          AppState(storage: storage, controller: FakeProxyController());
      addTearDown(state.dispose);
      await state.setNodeSort(NodeSort.latency);

      await openNodes(tester, state);

      // Both of Beta's nodes are faster than both of Alpha's, and both stay
      // below them: only the pair inside each section swapped.
      expect(
        renderedOrder(
          tester,
          ['Alpha Slow', 'Alpha Quick', 'Beta Slow', 'Beta Quick'],
        ),
        ['Alpha Quick', 'Alpha Slow', 'Beta Quick', 'Beta Slow'],
      );
    });

    testWidgets('nothing to sort with no nodes', (tester) async {
      final built = await buildState();
      await openNodes(tester, built.state);

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.sort_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
}
