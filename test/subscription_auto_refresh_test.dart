/// Re-fetching stale subscriptions once the tunnel is up.
///
/// A panel behind the censorship this app exists to get around cannot be
/// fetched before connecting, which is exactly when the user is least likely to
/// go and tap refresh themselves. So a connect does it for them — quietly, once
/// per app run, and only for sources old enough to have changed.
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

/// Answers a refresh without a network, recording which sources were asked.
class _FakeImporter extends Importer {
  _FakeImporter({this.error, this.nodes = const []});

  /// Thrown instead of fetching, when set.
  final Object? error;
  final List<ProxyNode> nodes;

  final refreshed = <String>[];

  @override
  Future<({Subscription subscription, List<ProxyNode> nodes})> refresh(
    Subscription subscription, {
    bool viaLocalProxy = false,
  }) async {
    refreshed.add(subscription.id);
    if (error != null) throw error!;
    return (
      subscription: subscription.copyWith(
        nodeCount: nodes.length,
        updatedAt: DateTime.now(),
        clearFailure: true,
      ),
      nodes: nodes,
    );
  }
}

/// A remote source last fetched [age] ago, or never when null.
Subscription remote(String id, {Duration? age}) => Subscription(
      id: id,
      name: 'Panel $id',
      kind: SubscriptionKind.remote,
      url: 'https://$id.example.com/sub?token=s3cr3t',
      updatedAt: age == null ? null : DateTime.now().subtract(age),
    );

Future<({AppState state, FakeProxyController controller})> stateWith(
  Importer importer, {
  required List<Subscription> subscriptions,
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

/// Reports the tunnel as up, the way the service would, and lets the unawaited
/// refreshes the transition starts run to completion.
Future<void> connect(FakeProxyController controller) async {
  controller.emit(
    ProxyState(stage: ProxyStage.connected, since: DateTime.now()),
  );
  await pumpEventQueue();
}

void main() {
  test('a stale source is re-fetched on connect', () async {
    final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
    final harness = await stateWith(
      importer,
      subscriptions: [remote('s1', age: const Duration(days: 3))],
    );

    await connect(harness.controller);

    expect(importer.refreshed, ['s1']);
    expect(harness.state.nodes.single.name, 'Tokyo');
  });

  test('a source that has never been fetched is stale', () async {
    final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
    final harness = await stateWith(importer, subscriptions: [remote('s1')]);

    await connect(harness.controller);

    expect(importer.refreshed, ['s1'],
        reason: 'no updatedAt is not a fresh one');
  });

  test('a source fetched minutes ago is left alone', () async {
    final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
    final harness = await stateWith(
      importer,
      subscriptions: [remote('s1', age: const Duration(minutes: 5))],
    );

    await connect(harness.controller);

    expect(importer.refreshed, isEmpty,
        reason: 'connecting is not a reason to re-fetch what is current');
  });

  test('only the stale sources are re-fetched', () async {
    final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
    final harness = await stateWith(
      importer,
      subscriptions: [
        remote('fresh', age: const Duration(hours: 1)),
        remote('stale', age: const Duration(hours: 20)),
      ],
    );

    await connect(harness.controller);

    expect(importer.refreshed, ['stale']);
  });

  test('a manual source is never fetched', () async {
    final importer = _FakeImporter();
    final harness = await stateWith(
      importer,
      subscriptions: const [
        Subscription(id: 's1', name: 'Pasted', kind: SubscriptionKind.manual),
      ],
    );

    await connect(harness.controller);

    expect(importer.refreshed, isEmpty,
        reason: 'there is no URL to fetch, and no notice to show about it');
  });

  test('it stays quiet', () async {
    final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
    final harness = await stateWith(
      importer,
      subscriptions: [remote('s1', age: const Duration(days: 3))],
    );

    await connect(harness.controller);

    expect(harness.state.takeNotice(), isNull,
        reason: 'the user asked to connect, not to update');
  });

  test('a failure is recorded on the row without a snackbar', () async {
    final importer = _FakeImporter(
      error: ImportException(
        'nothing answered',
        failure: SubscriptionFailure.unreachable,
      ),
    );
    final harness = await stateWith(
      importer,
      subscriptions: [remote('s1', age: const Duration(days: 3))],
    );

    await connect(harness.controller);

    expect(harness.state.subscriptions.single.lastFailure,
        SubscriptionFailure.unreachable,
        reason: 'the row is where the user would look for it');
    expect(harness.state.takeNotice(), isNull);
  });

  test('reconnecting does not fetch again', () async {
    final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
    final harness = await stateWith(
      importer,
      subscriptions: [remote('s1', age: const Duration(days: 3))],
    );

    await connect(harness.controller);
    harness.controller.emit(ProxyState.disconnected);
    await pumpEventQueue();
    await connect(harness.controller);

    expect(importer.refreshed, ['s1'],
        reason: 'one attempt per app run: an upstream that is unreachable from '
            'here would otherwise be hit on every connect');
  });

  test('a user tap during the automatic fetch does not double it', () async {
    final importer = _FakeImporter(nodes: [node('a', 'Tokyo')]);
    final harness = await stateWith(
      importer,
      subscriptions: [remote('s1', age: const Duration(days: 3))],
    );

    // No pumpEventQueue: the automatic refresh is still in flight.
    harness.controller.emit(
      ProxyState(stage: ProxyStage.connected, since: DateTime.now()),
    );
    await harness.state.refreshSubscription('s1');
    await pumpEventQueue();

    expect(importer.refreshed, ['s1'],
        reason: 'two fetches replacing the same nodes race, and the later '
            'answer is not necessarily the newer one');
  });
}
