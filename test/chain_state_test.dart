/// Chain links through [AppState]: persistence, live reload, and guards.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, fakePortAllocator, node;

Future<({AppState state, FakeProxyController controller, Storage storage})>
    _harness({List<ProxyNode> nodes = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  await storage.writeNodes(
      nodes.isEmpty ? [node('a', 'Front'), node('b', 'Upstream')] : nodes);
  final controller = FakeProxyController();
  return (
    state: AppState(
      storage: storage,
      controller: controller,
      portAllocator: fakePortAllocator,
    ),
    controller: controller,
    storage: storage,
  );
}

void main() {
  test('a chain is persisted and restored', () async {
    final h = await _harness();
    addTearDown(h.state.dispose);

    await h.state.setNodeDetour('a', 'b');

    expect(h.storage.readNodes().first.detourNodeId, 'b');
    final reopened = AppState(
      storage: h.storage,
      controller: FakeProxyController(),
    );
    addTearDown(reopened.dispose);
    expect(reopened.nodes.first.detourNodeId, 'b');
  });

  test('duplicate stored endpoints are collapsed in the rendered config',
      () async {
    final h = await _harness(
      nodes: [node('same', 'First'), node('same', 'Duplicate')],
    );
    addTearDown(h.state.dispose);

    final config = jsonDecode(h.state.previewConfig()) as Map<String, dynamic>;
    final nodeOutbounds = (config['outbounds'] as List)
        .where((item) => (item as Map)['type'] == 'trojan')
        .toList();
    expect(h.state.nodes, hasLength(2),
        reason: 'aliases remain visible in the node list');
    expect(nodeOutbounds, hasLength(1));
  });

  test('changing a chain while connected reloads the rendered detour',
      () async {
    final h = await _harness();
    addTearDown(h.state.dispose);

    await h.state.connect();
    await h.state.setNodeDetour('a', 'b');

    expect(h.controller.reloadedConfigs, hasLength(1));
    final config =
        jsonDecode(h.controller.reloadedConfigs.single) as Map<String, dynamic>;
    final front = (config['outbounds'] as List).cast<Map>().firstWhere(
          (outbound) =>
              outbound['tag'] == ConfigBuilder.outboundTag(node('a', 'Front')),
        );
    expect(front['detour'], ConfigBuilder.outboundTag(node('b', 'Upstream')));
  });

  test('state rejects self-links and cycles', () async {
    final h = await _harness(
      nodes: [
        node('a', 'Front').copyWith(detourNodeId: 'b'),
        node('b', 'Upstream'),
      ],
    );
    addTearDown(h.state.dispose);

    await h.state.setNodeDetour('b', 'b');
    await h.state.setNodeDetour('b', 'a');

    expect(h.state.nodes.first.detourNodeId, 'b');
    expect(h.state.nodes[1].detourNodeId, isNull);
  });
}
