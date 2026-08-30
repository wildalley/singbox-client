/// Switching between sources on the nodes page.
///
/// With two subscriptions every row of the first one sits above the second's, in
/// one scroll view — 56 nodes means scrolling past all 56. The source row and the
/// per-source fold both exist so that is not the only way; the row must not
/// appear for a single source, where it would only cost height.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/models/subscription.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, node;

Subscription _source(String id, String name) => Subscription(
      id: id,
      name: name,
      kind: SubscriptionKind.remote,
      url: 'https://$id.example.com/sub',
      nodeCount: 1,
    );

Future<AppState> _stateWith({
  required List<Subscription> subscriptions,
  required List<ProxyNode> nodes,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  await storage.writeSubscriptions(subscriptions);
  await storage.writeNodes(nodes);
  final state = AppState(storage: storage, controller: FakeProxyController());
  addTearDown(state.dispose);
  return state;
}

Future<void> _openNodes(WidgetTester tester, AppState state) async {
  // Taller than the 600pt default, because the page is a lazy sliver list: rows
  // below the viewport are never built, and every check below is about which
  // source a row belongs to rather than where it sits. Without the room, adding
  // anything above the sections — the Auto entry did — reads as a row that
  // vanished.
  tester.view
    ..physicalSize = const Size(800, 2000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(SingBoxApp(state: state));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.hub_outlined));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('two sources get a picker that shows one at a time',
      (tester) async {
    final state = await _stateWith(
      subscriptions: [_source('s1', 'Alpha'), _source('s2', 'Beta')],
      nodes: [
        node('a', 'Tokyo').copyWith(subscriptionId: 's1'),
        node('b', 'Osaka').copyWith(subscriptionId: 's2'),
      ],
    );

    await _openNodes(tester, state);

    // Everything, until a source is picked.
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Osaka'), findsOneWidget);

    // 'Beta' names both the chip and the section header, so tap the chip.
    await tester.tap(find.text('Beta').first);
    await tester.pumpAndSettle();

    expect(find.text('Osaka'), findsOneWidget);
    expect(find.text('Tokyo'), findsNothing,
        reason: 'the other source is what the picker exists to skip');

    await tester.tap(find.text('All sources'));
    await tester.pumpAndSettle();

    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Osaka'), findsOneWidget);
  });

  testWidgets('manually added nodes are one of the sources', (tester) async {
    final state = await _stateWith(
      subscriptions: [_source('s1', 'Alpha')],
      nodes: [
        node('a', 'Tokyo').copyWith(subscriptionId: 's1'),
        node('b', 'Pasted'),
      ],
    );

    await _openNodes(tester, state);

    // 'Manual' is the chip and the group label above the pasted node.
    await tester.tap(find.text('Manual').first);
    await tester.pumpAndSettle();

    expect(find.text('Pasted'), findsOneWidget);
    expect(find.text('Tokyo'), findsNothing);
  });

  testWidgets('a single source gets no picker row', (tester) async {
    final state = await _stateWith(
      subscriptions: [_source('s1', 'Alpha')],
      nodes: [node('a', 'Tokyo').copyWith(subscriptionId: 's1')],
    );

    await _openNodes(tester, state);

    expect(find.text('All sources'), findsNothing);
    expect(find.text('Tokyo'), findsOneWidget);
  });

  testWidgets('removing the selected source falls back to all of them',
      (tester) async {
    final state = await _stateWith(
      subscriptions: [_source('s1', 'Alpha'), _source('s2', 'Beta')],
      nodes: [
        node('a', 'Tokyo').copyWith(subscriptionId: 's1'),
        node('b', 'Osaka').copyWith(subscriptionId: 's2'),
      ],
    );

    await _openNodes(tester, state);
    await tester.tap(find.text('Beta').first);
    await tester.pumpAndSettle();

    await state.removeSubscription('s2');
    await tester.pumpAndSettle();

    // Not an empty list filtered by a source that no longer exists.
    expect(find.text('Tokyo'), findsOneWidget);
  });

  group('folding a source away', () {
    testWidgets('hides its rows and keeps its header', (tester) async {
      final state = await _stateWith(
        subscriptions: [_source('s1', 'Alpha')],
        nodes: [node('a', 'Tokyo').copyWith(subscriptionId: 's1')],
      );

      await _openNodes(tester, state);
      // Open by default: the common trip through this page is "arrive, tap a
      // node", and folded-by-default would make that two taps.
      expect(find.text('Tokyo'), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.text('Tokyo'), findsNothing);
      expect(find.text('Alpha'), findsOneWidget,
          reason: 'the header is what unfolds it again');

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.text('Tokyo'), findsOneWidget);
    });

    testWidgets('survives a restart', (tester) async {
      final state = await _stateWith(
        subscriptions: [_source('s1', 'Alpha')],
        nodes: [node('a', 'Tokyo').copyWith(subscriptionId: 's1')],
      );

      await _openNodes(tester, state);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      // A second run over the same store, the way the next app start reads it.
      final reloaded = AppState(
        storage: Storage(await SharedPreferences.getInstance()),
        controller: FakeProxyController(),
      );
      addTearDown(reloaded.dispose);
      // Straight to pumpWidget: the shell is the same widget type, so the nodes
      // tab it is already showing survives the swap.
      await tester.pumpWidget(SingBoxApp(state: reloaded));
      await tester.pumpAndSettle();

      expect(find.text('Tokyo'), findsNothing,
          reason: 'folding a long list away is work, and it should not be '
              'asked for again on every visit');
    });

    testWidgets('does not hide what a search turned up', (tester) async {
      final state = await _stateWith(
        subscriptions: [_source('s1', 'Alpha')],
        nodes: [node('a', 'Tokyo').copyWith(subscriptionId: 's1')],
      );

      await _openNodes(tester, state);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'tok');
      await tester.pumpAndSettle();

      // A match behind a chevron reads as "no results", not as folded.
      expect(find.text('Tokyo'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.text('Tokyo'), findsNothing,
          reason: 'searching shows through a fold, it does not undo it');
    });

    testWidgets('shows through when the source is the one picked',
        (tester) async {
      final state = await _stateWith(
        subscriptions: [_source('s1', 'Alpha'), _source('s2', 'Beta')],
        nodes: [
          node('a', 'Tokyo').copyWith(subscriptionId: 's1'),
          node('b', 'Osaka').copyWith(subscriptionId: 's2'),
        ],
      );

      await _openNodes(tester, state);
      // The chip comes first in the tree; the section header is the last.
      await tester.tap(find.text('Alpha').last);
      await tester.pumpAndSettle();
      expect(find.text('Tokyo'), findsNothing);

      await tester.tap(find.text('Alpha').first);
      await tester.pumpAndSettle();

      // Asking for only this source is not asking for an empty page.
      expect(find.text('Tokyo'), findsOneWidget);
      expect(state.isSourceCollapsed('s1'), isTrue,
          reason: 'the chip must not rewrite what the user folded');
    });

    testWidgets('is not what the buttons beside it do', (tester) async {
      final state = await _stateWith(
        subscriptions: [_source('s1', 'Alpha')],
        nodes: [node('a', 'Tokyo').copyWith(subscriptionId: 's1')],
      );

      await _openNodes(tester, state);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Tokyo'), findsOneWidget,
          reason: 'the delete button sits inside the tappable header');
      expect(state.isSourceCollapsed('s1'), isFalse);
    });

    testWidgets('works on the manual group too', (tester) async {
      final state = await _stateWith(
        subscriptions: [_source('s1', 'Alpha')],
        nodes: [
          node('a', 'Tokyo').copyWith(subscriptionId: 's1'),
          node('b', 'Pasted'),
        ],
      );

      await _openNodes(tester, state);
      // The group's label is a section label, so it is the uppercased one.
      await tester.tap(find.text('MANUAL'));
      await tester.pumpAndSettle();

      expect(find.text('Pasted'), findsNothing);
      expect(find.text('Tokyo'), findsOneWidget,
          reason: 'one source folded is not all of them');
    });

    testWidgets('leaves nothing behind when the source is removed',
        (tester) async {
      final state = await _stateWith(
        subscriptions: [_source('s1', 'Alpha'), _source('s2', 'Beta')],
        nodes: [
          node('a', 'Tokyo').copyWith(subscriptionId: 's1'),
          node('b', 'Osaka').copyWith(subscriptionId: 's2'),
        ],
      );

      await _openNodes(tester, state);
      await tester.tap(find.text('Beta').last);
      await tester.pumpAndSettle();

      await state.removeSubscription('s2');

      final stored = Storage(await SharedPreferences.getInstance());
      expect(stored.readCollapsedSources(), isNot(contains('s2')),
          reason: 'ids are never reused, so a kept one is dead weight');
    });
  });
}
