/// The console backdrop's signal field, and where its motion comes from.
///
/// The field used to be a fixed diagram on a free-running twelve-second loop. It
/// looked the same during a saturated download as through a tunnel carrying
/// nothing — a decoration that implied activity it knew nothing about — and it
/// had been mounted by nothing at all since the shell was split up, so no test
/// noticed either fact. Both are what this file holds: the field is fed the
/// tunnel's real throughput, and its motion starts and stops with that
/// throughput rather than running forever.
///
/// The perpetual ticker is worth naming as its own hazard. A `repeat()` behind
/// the whole app means no frame-settling wait ever finishes, so every widget test
/// that renders a connected app hangs on its ten-minute timeout instead of
/// failing — which is how this was found.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/proxy_state.dart';
import 'package:singbox_client/ui/components.dart';
import 'package:singbox_client/ui/theme.dart';

import 'widget_test.dart' show buildState, node;

/// The mounted backdrop, which is the seam: its inputs are what the painter
/// draws from, and asserting on them does not depend on pixels.
ConsoleBackground _backdrop(WidgetTester tester) =>
    tester.widget<ConsoleBackground>(find.byType(ConsoleBackground));

/// A backdrop on its own, for the motion assertions.
///
/// [WidgetTester.hasRunningAnimations] is tree-wide, and the dashboard behind
/// this thing animates plenty of its own — so mounting the whole app would make
/// the flag say nothing about this ticker in particular. Alone in the tree, it
/// says exactly one thing.
Widget _alone({
  List<int> downlink = const [],
  List<int> uplink = const [],
  bool reduceMotion = false,
}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(
          body: ConsoleBackground(
            animate: true,
            showSignals: true,
            downlink: downlink,
            uplink: uplink,
            child: const SizedBox(width: 400, height: 300),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the field is mounted on a connected dashboard', (tester) async {
    // The regression that made all of this dead code: nothing passed
    // showSignals, so the field could not appear however much traffic flowed.
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    harness.controller.emit(const ProxyState(stage: ProxyStage.connected));

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    expect(_backdrop(tester).showSignals, isTrue);
  });

  testWidgets('a disconnected app carries no field at all', (tester) async {
    // It reports throughput, and a disconnected tunnel has none to report.
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    expect(_backdrop(tester).showSignals, isFalse);
  });

  testWidgets("the samples reaching it are the tunnel's own", (tester) async {
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    harness.controller.emit(const ProxyState(stage: ProxyStage.connected));
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    harness.controller.emitTraffic(
      const ProxyTraffic(downlink: 4096, uplink: 512),
    );
    await tester.pumpAndSettle();

    final backdrop = _backdrop(tester);
    expect(backdrop.downlink, [4096],
        reason: 'the field draws the same history the traffic chart plots');
    expect(backdrop.uplink, [512]);
  });

  group('motion', () {
    testWidgets('an idle tunnel holds still', (tester) async {
      // Connected but carrying nothing. The graph stays drawn — it stands for
      // the tunnel, which is up — but a still field must not hold a ticker open.
      await tester.pumpWidget(_alone(downlink: const [0], uplink: const [0]));
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('traffic sets it moving, and it settles again', (tester) async {
      await tester.pumpWidget(_alone(downlink: const [0]));
      await tester.pump();

      await tester.pumpWidget(_alone(downlink: const [2 * 1024 * 1024]));
      await tester.pump();

      expect(tester.hasRunningAnimations, isTrue,
          reason: 'a reading arrived, so the field has something to show');

      // The point of a beat per reading rather than a repeat(): once the
      // readings stop the field comes to rest by itself, which is both honest
      // about the tunnel and what lets a settling wait ever finish.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('reduced motion keeps it still through a burst',
        (tester) async {
      await tester.pumpWidget(
        _alone(downlink: const [8 * 1024 * 1024], reduceMotion: true),
      );
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
      // The reading still reaches the painter — it is data, not an animation.
      expect(_backdrop(tester).downlink, [8 * 1024 * 1024]);
    });
  });
}
