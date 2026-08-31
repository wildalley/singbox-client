/// What a failed refresh leaves behind.
///
/// The reported bug was a subscription row reading `Subscription fetch failed:
/// HandshakeException: Connection terminated during handshake` inside a Chinese
/// UI: the exception message *was* the message, and it was also persisted. So
/// these tests assert on the recorded reason, never on a sentence.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/importer.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/models/proxy_state.dart';
import 'package:singbox_client/models/subscription.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, node;

/// Answers a refresh without a network, recording how it was asked to travel.
class _FakeImporter extends Importer {
  _FakeImporter({this.error, this.nodes = const []});

  /// Thrown instead of fetching, when set.
  final Object? error;
  final List<ProxyNode> nodes;

  final viaLocalProxyCalls = <bool>[];

  @override
  Future<({Subscription subscription, List<ProxyNode> nodes})> refresh(
    Subscription subscription, {
    bool viaLocalProxy = false,
  }) async {
    viaLocalProxyCalls.add(viaLocalProxy);
    if (error != null) throw error!;
    return (
      subscription: subscription.copyWith(
        nodeCount: nodes.length,
        updatedAt: DateTime(2026, 8, 30),
        clearFailure: true,
      ),
      nodes: nodes,
    );
  }
}

const _remote = Subscription(
  id: 's1',
  name: 'Panel',
  kind: SubscriptionKind.remote,
  url: 'https://panel.example.com/sub?token=s3cr3t',
);

Future<({AppState state, FakeProxyController controller})> stateWith(
  Importer importer, {
  List<Subscription> subscriptions = const [_remote],
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  await storage.writeSubscriptions(subscriptions);
  final controller = FakeProxyController();
  final state = AppState(
    storage: storage,
    controller: controller,
    importer: importer,
  );
  addTearDown(state.dispose);
  return (state: state, controller: controller);
}

void main() {
  test('a failed refresh records the reason, not a sentence', () async {
    final importer = _FakeImporter(
      error: ImportException(
        'HTTP 403 from https://panel.example.com/sub?token=s3cr3t',
        failure: SubscriptionFailure.httpStatus,
        statusCode: 403,
      ),
    );
    final harness = await stateWith(importer);

    await harness.state.refreshSubscription('s1');

    final subscription = harness.state.subscriptions.single;
    expect(subscription.lastFailure, SubscriptionFailure.httpStatus);
    expect(subscription.lastFailureStatus, 403);

    final notice = harness.state.takeNotice()!;
    expect(notice.kind, NoticeKind.importFailed);
    expect(notice.failure, SubscriptionFailure.httpStatus);
    expect(notice.count, 403);
    // The English message and the token both stay out of anything the UI reads.
    expect(notice.detail, isNull);
  });

  test('the recorded reason survives a reload of the app', () async {
    final harness = await stateWith(
      _FakeImporter(error: ImportException('nothing answered',
          failure: SubscriptionFailure.unreachable)),
    );

    await harness.state.refreshSubscription('s1');
    // The same preferences, read the way the next launch reads them.
    final reloaded = Storage(await SharedPreferences.getInstance());

    expect(reloaded.readSubscriptions().single.lastFailure,
        SubscriptionFailure.unreachable);
  });

  test('a later success clears the failure', () async {
    final failing = await stateWith(
      _FakeImporter(error: ImportException('nothing answered',
          failure: SubscriptionFailure.unreachable)),
    );
    await failing.state.refreshSubscription('s1');
    expect(failing.state.subscriptions.single.lastFailure, isNotNull);

    final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
    final harness = await stateWith(
      importer,
      subscriptions: [failing.state.subscriptions.single],
    );

    await harness.state.refreshSubscription('s1');

    expect(harness.state.subscriptions.single.lastFailure, isNull);
    expect(harness.state.subscriptions.single.lastFailureStatus, isNull);
  });

  test('an error that is not an import failure is not blamed on the source',
      () async {
    final harness = await stateWith(_FakeImporter(error: StateError('bug')));

    await harness.state.refreshSubscription('s1');

    expect(harness.state.subscriptions.single.lastFailure, isNull,
        reason: 'a bug here says nothing about the subscription');
    expect(harness.state.takeNotice()!.kind, NoticeKind.passthrough);
  });

  group('how the request travels', () {
    test('disconnected, it goes out directly', () async {
      final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
      final harness = await stateWith(importer);

      await harness.state.refreshSubscription('s1');

      expect(importer.viaLocalProxyCalls, [false]);
    });

    test('connected, the tunnel is offered', () async {
      // A blocked panel is only reachable through the config's loopback
      // inbound: the app itself is excluded from the VPN.
      final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
      // Freshly fetched, so connecting does not add an automatic refresh to the
      // one call this test is counting.
      final harness = await stateWith(
        importer,
        subscriptions: [_remote.copyWith(updatedAt: DateTime.now())],
      );
      harness.controller.emit(
        ProxyState(stage: ProxyStage.connected, since: DateTime(2026, 8, 30)),
      );
      await pumpEventQueue();

      await harness.state.refreshSubscription('s1');

      expect(importer.viaLocalProxyCalls, [true]);
    });
  });
}
