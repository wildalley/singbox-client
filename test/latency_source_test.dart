/// Where a latency figure comes from.
///
/// Two measurements share one button. Connected, the engine URL-tests the
/// selector group and reports what a real request through each proxy cost;
/// disconnected, there is no tunnel to measure through, so TCP-based nodes get
/// a TCP handshake while UDP/QUIC nodes remain untested. These tests hold the
/// boundary between them:
/// which path runs, how the engine's tag-keyed results find their way back to
/// nodes, and what happens to members the engine never reports.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/config_builder.dart';

import 'widget_test.dart' show FakeLatencyTester, buildState, node;

void main() {
  group('disconnected', () {
    test('probes the nodes directly', () async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo'), node('b', 'Osaka')],
        latencyTester: const FakeLatencyTester({'a': 42, 'b': 91}),
      );
      addTearDown(harness.state.dispose);

      await harness.state.testLatency();

      expect(
        {for (final n in harness.state.nodes) n.id: n.latencyMs},
        {'a': 42, 'b': 91},
      );
      expect(harness.controller.urlTestCount, 0,
          reason: 'there is no tunnel to measure through');
    });

    test('an unanswered handshake is unreachable', () async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo'), node('b', 'Osaka')],
        latencyTester: const FakeLatencyTester({'a': 42}),
      );
      addTearDown(harness.state.dispose);

      await harness.state.testLatency();

      expect(harness.state.nodes.last.isUnreachable, isTrue);
    });
  });

  group('connected', () {
    test('asks the engine and maps tags back to nodes', () async {
      final nodes = [node('a', 'Tokyo'), node('b', 'Osaka')];
      final harness = await buildState(
        nodes: nodes,
        // Deliberately different figures: if these show up, the fallback ran.
        latencyTester: const FakeLatencyTester({'a': 999, 'b': 999}),
      );
      addTearDown(harness.state.dispose);
      final state = harness.state;
      await state.connect();

      // The engine reports as soon as the request is handed over, so answer the
      // urlTest call rather than waiting for testLatency to return.
      final done = state.testLatency();
      await pumpEventQueue();
      harness.controller.emitGroup({
        ConfigBuilder.outboundTag(state.nodes.first): 42,
        ConfigBuilder.outboundTag(state.nodes.last): 91,
      });
      await done;

      expect(harness.controller.urlTestCount, 1);
      expect(
        {for (final n in state.nodes) n.id: n.latencyMs},
        {'a': 42, 'b': 91},
        reason: 'only ConfigBuilder.outboundTag leads from a tag back to a node',
      );
    });

    test('members the engine does not name are left alone', () async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo')],
        latencyTester: const FakeLatencyTester({'a': 999}),
      );
      addTearDown(harness.state.dispose);
      final state = harness.state;
      await state.connect();

      final done = state.testLatency();
      await pumpEventQueue();
      // The urltest group is a member of the selector, and matches no node.
      harness.controller.emitGroup({
        ConfigTags.auto: 30,
        ConfigBuilder.outboundTag(state.nodes.single): 42,
      });
      await done;

      expect(state.nodes.single.latencyMs, 42);
    });

    test('a zero delay is not a measurement', () async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo'), node('b', 'Osaka')],
        latencyTester: const FakeLatencyTester({'a': 999, 'b': 999}),
        // The second node never reports, so this test is the wait expiring.
        urlTestTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(harness.state.dispose);
      final state = harness.state;
      await state.connect();

      final done = state.testLatency();
      await pumpEventQueue();
      harness.controller.emitGroup({
        ConfigBuilder.outboundTag(state.nodes.first): 42,
        // libbox's "no result": never tested, or the test failed.
        ConfigBuilder.outboundTag(state.nodes.last): 0,
      });
      // Nothing more is coming for the second node, so the wait has to expire.
      await done;

      expect(state.nodes.first.latencyMs, 42);
      expect(state.nodes.last.isUnreachable, isTrue,
          reason: 'a URL test that reported nothing failed, which is what the '
              'user needs to see — not an empty row');
    });

    test('a tunnel that went away falls back to probing', () async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo')],
        latencyTester: const FakeLatencyTester({'a': 42}),
      );
      addTearDown(harness.state.dispose);
      final state = harness.state;
      await state.connect();
      // Reports connected, but the call fails — the window between the two.
      harness.controller.urlTestFails = true;

      await state.testLatency();

      expect(harness.controller.urlTestCount, 1);
      expect(state.nodes.single.latencyMs, 42,
          reason: 'the handshake figure is worse, but it is a figure');
    });

    test('the run ends once every member has reported', () async {
      final harness = await buildState(
        nodes: [node('a', 'Tokyo')],
        latencyTester: const FakeLatencyTester({'a': 999}),
        // Long enough that reaching it would hang the test rather than pass it:
        // finishing here has to come from the last member reporting.
        urlTestTimeout: const Duration(minutes: 5),
      );
      addTearDown(harness.state.dispose);
      final state = harness.state;
      await state.connect();
      await pumpEventQueue();

      final done = state.testLatency();
      await pumpEventQueue();
      harness.controller
          .emitGroup({ConfigBuilder.outboundTag(state.nodes.single): 42});
      await done;

      expect(state.nodes.single.latencyMs, 42);
      expect(state.isTestingLatency, isFalse);
    });
  });

  test('a second run while one is in flight is ignored', () async {
    final harness = await buildState(
      nodes: [node('a', 'Tokyo')],
      latencyTester: const FakeLatencyTester({'a': 42}),
    );
    addTearDown(harness.state.dispose);
    final state = harness.state;

    await Future.wait([state.testLatency(), state.testLatency()]);

    expect(state.nodes.single.latencyMs, 42);
  });
}
