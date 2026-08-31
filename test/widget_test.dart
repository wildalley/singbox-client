/// UI tests driven by a fake [ProxyController], so no VPN or native code runs.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/data/latency_tester.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/models/proxy_state.dart';
import 'package:singbox_client/platform/proxy_controller.dart';
import 'package:singbox_client/state/app_state.dart';

/// Records calls and lets tests push state, the way the service would.
class FakeProxyController implements ProxyController {
  final _states = StreamController<ProxyState>.broadcast();
  final _traffic = StreamController<ProxyTraffic>.broadcast();
  final _logs = StreamController<ProxyLogEntry>.broadcast();
  final _groups = StreamController<ProxyGroup>.broadcast();

  var _state = ProxyState.disconnected;

  bool permissionGranted = true;
  final startedConfigs = <String>[];
  final selectedOutbounds = <String>[];
  var stopCount = 0;
  var urlTestCount = 0;

  /// When set, [urlTest] throws instead of reporting, standing in for a tunnel
  /// that went away between the connected check and the call.
  bool urlTestFails = false;

  @override
  Stream<ProxyState> get states => _states.stream;

  @override
  Stream<ProxyTraffic> get traffic => _traffic.stream;

  @override
  Stream<ProxyLogEntry> get logs => _logs.stream;

  @override
  Stream<ProxyGroup> get groups => _groups.stream;

  @override
  ProxyState get currentState => _state;

  void emit(ProxyState state) {
    _state = state;
    _states.add(state);
  }

  void emitTraffic(ProxyTraffic value) => _traffic.add(value);

  /// Emits a log line, defaulting to now.
  ///
  /// [at] exists for the visual snapshots: the logs page renders each entry's
  /// `hh:mm:ss`, so a wall-clock default would change the golden on every run.
  void emitLog(String message, {DateTime? at}) =>
      _logs.add(ProxyLogEntry(message: message, at: at ?? DateTime.now()));

  /// Reports URL-test delays the way the engine's group subscription does:
  /// [delays] maps an outbound tag to milliseconds, where 0 means "no result".
  void emitGroup(
    Map<String, int> delays, {
    String tag = ConfigTags.proxy,
    String selected = '',
  }) =>
      _groups.add(ProxyGroup(tag: tag, selected: selected, delays: delays));

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> start(String configJson) async {
    startedConfigs.add(configJson);
    emit(ProxyState(stage: ProxyStage.connected, since: DateTime.now()));
  }

  @override
  Future<void> stop() async {
    stopCount++;
    emit(ProxyState.disconnected);
  }

  @override
  Future<void> reload(String configJson) async =>
      startedConfigs.add(configJson);

  @override
  Future<void> selectOutbound(String outboundTag) async =>
      selectedOutbounds.add(outboundTag);

  @override
  Future<void> urlTest() async {
    urlTestCount++;
    if (urlTestFails) throw StateError('not connected');
  }

  @override
  Future<String?> coreVersion() async => 'v1.13.19';

  @override
  void dispose() {
    _states.close();
    _traffic.close();
    _logs.close();
    _groups.close();
  }
}

ProxyNode node(String id, String name) => ProxyNode(
      id: id,
      name: name,
      protocol: NodeProtocol.trojan,
      server: '$id.example.com',
      serverPort: 443,
      raw: const {'password': 'secret'},
    );

/// Answers from a table instead of opening sockets.
///
/// Only [probe] is overridden: `probeAll` is the real one, so tests still go
/// through its concurrency pump rather than a stand-in for it.
class FakeLatencyTester extends LatencyTester {
  const FakeLatencyTester(this.latencies);

  /// Node id to milliseconds. Anything missing comes back unreachable.
  final Map<String, int> latencies;

  @override
  Future<int> probe(ProxyNode node) async =>
      latencies[node.id] ?? ProxyNode.unreachableLatency;
}

Future<({AppState state, FakeProxyController controller})> buildState({
  List<ProxyNode> nodes = const [],
  LatencyTester? latencyTester,
  Duration? urlTestTimeout,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  if (nodes.isNotEmpty) await storage.writeNodes(nodes);
  final controller = FakeProxyController();
  return (
    state: AppState(
      storage: storage,
      controller: controller,
      latencyTester: latencyTester,
      urlTestTimeout: urlTestTimeout,
    ),
    controller: controller,
  );
}

void main() {
  testWidgets('empty state prompts for an import instead of connecting',
      (tester) async {
    final harness = await buildState();
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    expect(find.text('No nodes yet'), findsOneWidget);
    // Nothing to connect to, so the control invites an import.
    expect(find.text('Add nodes'), findsWidgets);
    expect(harness.controller.startedConfigs, isEmpty);
  });

  testWidgets('connecting sends a rendered config and shows connected state',
      (tester) async {
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    expect(find.text('Disconnected'), findsWidgets);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(harness.controller.startedConfigs, hasLength(1));
    // The config the UI sends must be the real thing, not a placeholder.
    expect(harness.controller.startedConfigs.single, contains('"type": "tun"'));
    expect(harness.controller.startedConfigs.single, contains('a.example.com'));
    expect(find.text('Connected'), findsWidgets);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets('disconnect stops the tunnel', (tester) async {
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();

    expect(harness.controller.stopCount, 1);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('denied permission surfaces an error and starts nothing',
      (tester) async {
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    harness.controller.permissionGranted = false;

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(harness.controller.startedConfigs, isEmpty);
    expect(find.text('VPN permission denied'), findsOneWidget);
  });

  testWidgets('a long engine error stays inside its snackbar', (tester) async {
    // Verbatim from a device: three rule-sets failing DNS, each quoting a URL
    // and a socket address. Unbounded, this laid itself across the dial, the
    // connect button and the traffic card. Every other test seeds a short
    // message, which is exactly why that shipped.
    const engineError =
        'initialize rule-set[2]: initial rule-set: geosite-ads: Get '
        '"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/'
        'geosite-category-ads-all.srs": lookup raw.githubusercontent.com: '
        'read udp [::1]:59673->[::1]:53: read: connection refused | '
        'initialize rule-set[1]: initial rule-set: geoip-cn: Get '
        '"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/'
        'geoip-cn.srs": lookup raw.githubusercontent.com: read udp '
        '[::1]:59673->[::1]:53: read: connection refused | '
        'initialize rule-set[0]: initial rule-set: geosite-cn: Get '
        '"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/'
        'geosite-geolocation-cn.srs": lookup raw.githubusercontent.com: '
        'read udp [::1]:59673->[::1]:53: read: connection refused';

    final harness = await buildState(nodes: [node('a', 'HK-1')]);
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    harness.controller.emit(const ProxyState(
      stage: ProxyStage.error,
      message: engineError,
    ));
    await tester.pumpAndSettle();

    // An unbounded paragraph in a floating snackbar overflows its bar, and a
    // RenderFlex/paint overflow is an exception in tests.
    expect(tester.takeException(), isNull);

    // Both places the message surfaces are clamped: the snackbar and the dial's
    // detail line under it.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .where((text) => (text.data ?? '').contains('rule-set'))
        .toList();
    expect(texts, isNotEmpty, reason: 'the error should reach the screen');
    for (final text in texts) {
      expect(text.maxLines, isNotNull,
          reason: 'engine text must be clamped: ${text.data?.substring(0, 40)}');
      expect(text.overflow, TextOverflow.ellipsis);
    }
  });

  testWidgets('traffic events reach the home screen', (tester) async {
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    harness.controller.emitTraffic(const ProxyTraffic(
      downlink: 2 * 1024 * 1024,
      downlinkTotal: 5 * 1024 * 1024,
    ));
    await tester.pumpAndSettle();

    expect(find.text('2.0 MB/s'), findsWidgets);
    expect(find.text('5.0 MB'), findsWidgets);
  });

  testWidgets('selecting another node while connected switches the outbound',
      (tester) async {
    final harness = await buildState(
      nodes: [node('a', 'Tokyo'), node('b', 'Osaka')],
    );
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.hub_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Osaka'));
    await tester.pumpAndSettle();

    // Live switch, not a restart.
    expect(harness.controller.selectedOutbounds, hasLength(1));
    expect(harness.controller.selectedOutbounds.single, contains('Osaka'));
    expect(harness.controller.stopCount, 0);
  });

  testWidgets('logs tab shows engine output', (tester) async {
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    harness.controller.emitLog('inbound/tun: started at tun0');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('started at tun0'), findsOneWidget);
  });

  testWidgets('log lines arrive without their terminal colouring',
      (tester) async {
    // libbox writes for a terminal, so a real line looks like this. Flutter
    // renders each escape as a tofu box, and they travel into "Copy all".
    const raw = '\x1B[37mDEBUG\x1B[0m[0000] '
        '[\x1B[38;5;83m1604613780\x1B[0m 102ms] '
        'connection: connection upload finished';
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    harness.controller.emitLog(raw);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();

    expect(
      harness.state.logs.single.message,
      'DEBUG[0000] [1604613780 102ms] connection: connection upload finished',
      reason: 'the uptime field is libbox output, only the escapes are not',
    );
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .where((text) => (text.data ?? '').contains('\x1B')),
      isEmpty,
    );
  });

  testWidgets('settings reports the core version from the platform',
      (tester) async {
    final harness = await buildState();
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // The About group sits at the bottom of the page.
    await tester.scrollUntilVisible(find.text('sing-box core'), 200);
    await tester.pumpAndSettle();

    expect(find.text('v1.13.19'), findsOneWidget);
  });

  testWidgets('desktop layout renders the rail without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);

    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
