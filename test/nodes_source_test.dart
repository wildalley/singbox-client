/// Switching between sources on the nodes page.
///
/// With two subscriptions every row of the first one sits above the second's, in
/// one scroll view — 56 nodes means scrolling past all 56. The source row and the
/// per-source fold both exist so that is not the only way; the row must not
/// appear for a single source, where it would only cost height.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show RenderObject, RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/latency_tester.dart';
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
  LatencyTester? latencyTester,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  await storage.writeSubscriptions(subscriptions);
  await storage.writeNodes(nodes);
  final state = AppState(
    storage: storage,
    controller: FakeProxyController(),
    latencyTester: latencyTester,
  );
  addTearDown(state.dispose);
  return state;
}

class _HeldLatencyTester extends LatencyTester {
  final gate = Completer<void>();

  @override
  Future<int> probe(ProxyNode node) async {
    await gate.future;
    return 42;
  }
}

Future<void> _openNodes(
  WidgetTester tester,
  AppState state, {
  Size size = const Size(800, 2000),
}) async {
  // Taller than the 600pt default, because the page is a lazy sliver list: rows
  // below the viewport are never built, and every check below is about which
  // source a row belongs to rather than where it sits. Without the room, adding
  // anything above the sections — the Auto entry did — reads as a row that
  // vanished.
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Live Linux tests use their own logical viewport independently of the view.
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(SingBoxApp(state: state));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.hub_outlined).first);
  await tester.pumpAndSettle();
}

int _renderedNodeLabels(WidgetTester tester, Set<String> names) {
  var count = 0;
  void visit(RenderObject object) {
    if (object is RenderParagraph &&
        names.contains(object.text.toPlainText())) {
      count++;
    }
    object.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  return count;
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
    for (final manual in [false, true]) {
      testWidgets(
          '${manual ? 'manual group' : 'subscription'} with repeated endpoint '
          'IDs leaves no rows after folding', (tester) async {
        final sourceId = manual ? null : 's1';
        final state = await _stateWith(
          subscriptions: manual ? [] : [_source('s1', 'Alpha')],
          nodes: [
            node('a', 'Tokyo').copyWith(subscriptionId: sourceId),
            node('b', 'Osaka').copyWith(subscriptionId: sourceId),
            // A subscription can publish an endpoint under another name, or
            // repeat the very same entry. Both cases retain its endpoint ID.
            node('a', 'Tokyo alias').copyWith(subscriptionId: sourceId),
            node('b', 'Osaka').copyWith(subscriptionId: sourceId),
          ],
        );
        await _openNodes(tester, state);
        final header = find.text(manual ? 'MANUAL' : 'Alpha');
        for (var i = 0; i < 3; i++) {
          expect(find.text('Tokyo'), findsOneWidget);
          expect(find.text('Tokyo alias'), findsOneWidget);
          expect(find.text('Osaka'), findsNWidgets(2));
          await tester.tap(header, kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          expect(find.text('Tokyo'), findsNothing);
          expect(find.text('Tokyo alias'), findsNothing);
          expect(find.text('Osaka'), findsNothing);
          // Duplicate keys can leave orphaned render objects even after the
          // element tree (and therefore find.text) has forgotten the rows.
          expect(_renderedNodeLabels(tester, {'Tokyo', 'Tokyo alias', 'Osaka'}),
              0);

          await tester.tap(header, kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
        }
        expect(state.nodes, hasLength(4),
            reason: 'folding must not discard aliases or repeated entries');
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
    }

    testWidgets('responds while latency testing is still running',
        (tester) async {
      final latencyTester = _HeldLatencyTester();
      addTearDown(() {
        if (!latencyTester.gate.isCompleted) latencyTester.gate.complete();
      });
      final state = await _stateWith(
        subscriptions: [_source('s1', 'Alpha')],
        nodes: [node('a', 'Tokyo').copyWith(subscriptionId: 's1')],
        latencyTester: latencyTester,
      );
      await _openNodes(tester, state);

      final testing = state.testLatency();
      await tester.pump();
      for (final collapsed in [true, false, true]) {
        await tester.tap(find.text('Alpha'));
        // The probe spinner stays active until the gate is released.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(state.isTestingLatency, isTrue);
        expect(find.text('Tokyo'), collapsed ? findsNothing : findsOneWidget);
      }

      latencyTester.gate.complete();
      await tester.pumpAndSettle();
      await testing;
      expect(find.text('Tokyo'), findsNothing);
      expect(state.nodes.single.latencyMs, 42);
      final stored = Storage(await SharedPreferences.getInstance());
      expect(stored.readCollapsedSources(), contains('s1'),
          reason: 'the final fold must persist after queued work completes');
    });

    testWidgets('Linux mouse can repeatedly fold a long subscription',
        (tester) async {
      const counts = [72, 20, 2, 46, 13];
      // Same duplicate-ID positions as the affected 46-entry subscription,
      // with synthetic names/servers and no user credentials.
      const repeats = {22: 7, 38: 10, 15: 13, 25: 21};
      final state = await _stateWith(
        subscriptions: [
          for (var i = 0; i < counts.length; i++)
            _source('s$i', i.isOdd ? 'Imported' : 'Source $i'),
        ],
        nodes: [
          for (var i = 0; i < counts.length; i++)
            for (var j = 0; j < counts[i]; j++)
              node('$i-${i == 3 ? repeats[j] ?? j : j}', 'Node $i-$j')
                  .copyWith(subscriptionId: 's$i'),
        ],
      );
      for (var i = 0; i < counts.length; i++) {
        await state.toggleSourceCollapsed('s$i');
      }
      await _openNodes(tester, state, size: const Size(1270, 720));

      final header = find.text('Imported').last;
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(header, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.text('Node 3-0'), findsOneWidget);
        expect(state.isSourceCollapsed('s3'), isFalse);

        await tester.tap(header, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.textContaining('Node 3-'), findsNothing);
        expect(
            _renderedNodeLabels(tester, {
              for (var j = 0; j < counts[3]; j++) 'Node 3-$j',
            }),
            0);
        expect(state.isSourceCollapsed('s3'), isTrue);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    for (final initiallyCollapsed in [false, true]) {
      for (final search in [false, true]) {
        testWidgets(
            'can fold and reopen ${initiallyCollapsed ? 'folded' : 'open'} '
            'source revealed by ${search ? 'search' : 'source picker'}',
            (tester) async {
          final state = await _stateWith(
            subscriptions: [_source('s1', 'Alpha'), _source('s2', 'Beta')],
            nodes: [
              node('a', 'Tokyo').copyWith(subscriptionId: 's1'),
              node('b', 'Osaka').copyWith(subscriptionId: 's2'),
            ],
          );
          if (initiallyCollapsed) await state.toggleSourceCollapsed('s1');
          await _openNodes(tester, state);

          if (search) {
            await tester.enterText(find.byType(TextField), 'tok');
          } else {
            await tester.tap(find.text('Alpha').first);
          }
          await tester.pumpAndSettle();
          expect(find.text('Tokyo'), findsOneWidget);

          for (var i = 0; i < 2; i++) {
            await tester.tap(find.text('Alpha').last);
            await tester.pumpAndSettle();
            expect(find.text('Tokyo'), findsNothing);

            await tester.tap(find.text('Alpha').last);
            await tester.pumpAndSettle();
            expect(find.text('Tokyo'), findsOneWidget);
          }
          expect(state.isSourceCollapsed('s1'), initiallyCollapsed);

          await tester.tap(find.text('Alpha').last);
          await tester.pumpAndSettle();
          expect(find.text('Tokyo'), findsNothing);
          if (search) {
            await tester.enterText(find.byType(TextField), '');
          } else {
            await tester.tap(find.text('All sources'));
          }
          await tester.pumpAndSettle();
          expect(find.text('Tokyo'),
              initiallyCollapsed ? findsNothing : findsOneWidget);

          if (search) {
            await tester.enterText(find.byType(TextField), 'tokyo');
          } else {
            await tester.tap(find.text('Alpha').first);
          }
          await tester.pumpAndSettle();
          expect(find.text('Tokyo'), findsOneWidget,
              reason: 'a new filter must reveal its matches again');
        });
      }
    }

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

      // The source filter reveals a folded section, but the header still has to
      // be able to close it again. This was the regression: the forced-open
      // filter won over every later tap.
      await tester.tap(find.text('Alpha').last);
      await tester.pumpAndSettle();
      expect(find.text('Tokyo'), findsNothing);
      expect(state.isSourceCollapsed('s1'), isTrue,
          reason: 'a temporary filter close must preserve the fold state');
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
