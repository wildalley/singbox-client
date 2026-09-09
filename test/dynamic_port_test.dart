/// The loopback ports a session renders, and the gate every config passes.
///
/// Two things this pins. First, the ports the allocator chose have to reach the
/// config the runtime is started with — the whole feature is worthless if a
/// session moves off a taken port and then renders the taken one anyway, and
/// worse than worthless if the Clash API and the local inbound disagree about
/// where the tunnel listens.
///
/// Second, the config is validated on the way out rather than by each platform on
/// the way in. The desktop controllers parse their input and can refuse it;
/// Android hands the JSON straight to libbox, so before this gate existed an
/// unusable config reached the engine unexamined and surfaced as whatever the
/// engine made of it. Validating once, here, means every platform gets the same
/// verdict — and gets it before a process starts.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/data/port_allocator.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/models/proxy_state.dart';
import 'package:singbox_client/platform/config_facts.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, fakePortAllocator, node;

/// An allocator that answers with [ports], ignoring what was preferred.
///
/// Stands in for the machine this feature exists for: something else already
/// holds the documented pair, so the OS hands out two other numbers.
PortAllocator _allocator(LoopbackPorts ports) => ({
      required int preferredClashApiPort,
      required int preferredLocalProxyPort,
    }) async =>
        ports;

Future<({AppState state, FakeProxyController controller})> _build({
  PortAllocator? portAllocator,
  AppSettings settings = const AppSettings(),
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  await storage.writeNodes([node('a', 'Tokyo')]);
  await storage.writeSettings(settings);
  final controller = FakeProxyController();
  final state = AppState(
    storage: storage,
    controller: controller,
    portAllocator: portAllocator ?? fakePortAllocator,
  );
  addTearDown(state.dispose);
  return (state: state, controller: controller);
}

/// The Clash API port and every `mixed` inbound port in a rendered config.
({int clashPort, List<int> mixedPorts}) _ports(String configJson) {
  final config = jsonDecode(configJson) as Map;
  final controller = ((config['experimental'] as Map)['clash_api']
      as Map)['external_controller'] as String;
  final mixed = (config['inbounds'] as List)
      .cast<Map<String, dynamic>>()
      .where((inbound) => inbound['type'] == 'mixed')
      .map((inbound) => inbound['listen_port'] as int)
      .toList();
  return (
    clashPort: int.parse(controller.split(':').last),
    mixedPorts: mixed,
  );
}

void main() {
  group('the rendered ports', () {
    test('are the ones the allocator chose, not the defaults', () async {
      final harness = await _build(
        portAllocator: _allocator((clashApiPort: 31234, localProxyPort: 31235)),
      );

      await harness.state.connect();

      final ports = _ports(harness.controller.startedConfigs.single);
      expect(ports.clashPort, 31234);
      expect(ports.mixedPorts, [31235],
          reason: 'the inbound the app reaches the tunnel through has to be the '
              'one the core was told to bind');
      // Guards the failure this feature exists to avoid: a session that moved
      // off a taken port but rendered the taken one anyway would look like it
      // worked here while failing to bind on the machine.
      expect(ports.clashPort, isNot(ConfigBuilder.defaultClashApiPort));
      expect(ports.mixedPorts, isNot(contains(
        ConfigBuilder.defaultLocalProxyPort,
      )));
    });

    test('stay put across a reload', () async {
      // A reload renders afresh against a core that is already listening. New
      // numbers there would cut the control channel the desktop runtimes poll,
      // so the session's pair has to survive the second render.
      final harness = await _build(
        portAllocator: _allocator((clashApiPort: 31300, localProxyPort: 31301)),
      );
      await harness.state.connect();
      harness.controller.emit(const ProxyState(stage: ProxyStage.connected));

      await harness.state.applySettings(
        const AppSettings(proxyMode: ProxyMode.tun),
      );

      expect(harness.controller.reloadedConfigs, isNotEmpty,
          reason: 'a runtime setting changed, so the tunnel must be reloaded');
      final ports = _ports(harness.controller.reloadedConfigs.last);
      expect(ports.clashPort, 31300);
      expect(ports.mixedPorts, [31301]);
    });

    test('fall back to the documented pair when the draw fails', () async {
      // The allocator only probes, so a failure means "nothing is known to be
      // taken" — which is exactly the state every build was in before it
      // existed. A start is too important to abandon over it.
      final harness = await _build(
        portAllocator: ({
          required int preferredClashApiPort,
          required int preferredLocalProxyPort,
        }) async =>
            throw const SocketException('no sockets today'),
      );

      await harness.state.connect();

      final ports = _ports(harness.controller.startedConfigs.single);
      expect(ports.clashPort, ConfigBuilder.defaultClashApiPort);
      expect(ports.mixedPorts, [ConfigBuilder.defaultLocalProxyPort]);
    });

    test('the preview shows the documented pair while disconnected', () async {
      // Nothing has been allocated yet, and the preview is a document rather
      // than a session — showing an ephemeral number there would be a lie about
      // what the next start will do.
      final harness = await _build();

      final ports = _ports(harness.state.previewConfig());

      expect(ports.clashPort, ConfigBuilder.defaultClashApiPort);
      expect(ports.mixedPorts, [ConfigBuilder.defaultLocalProxyPort]);
    });
  });

  group('the validation gate', () {
    test('every started config satisfies the desktop parser', () async {
      // The assertion the gate makes on Android's behalf: libbox is handed the
      // same JSON the desktop controllers would accept, so a config that could
      // not name its own control plane never reaches an engine.
      final harness = await _build();

      await harness.state.connect();

      expect(
        () => ConfigFacts.parse(harness.controller.startedConfigs.single),
        returnsNormally,
      );
    });

    test('a rendered config carries what the runtimes need', () async {
      final harness = await _build(
        portAllocator: _allocator((clashApiPort: 31400, localProxyPort: 31401)),
      );

      await harness.state.connect();
      final facts = ConfigFacts.parse(
        harness.controller.startedConfigs.single,
      );

      expect(facts.clashPort, 31400);
      expect(facts.mixedPort, 31401);
      expect(facts.clashSecret, isNotEmpty,
          reason: 'an empty token would leave the control API open to every '
              'other app on the device');
    });
  });
}
