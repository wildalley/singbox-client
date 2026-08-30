/// Pixel-accurate screen snapshots, rendered as golden PNGs in
/// `test/snapshots/`.
///
/// Not part of the default suite: font rasterization is machine-dependent, so
/// these would be flaky as CI goldens. They exist as a design-review loop —
/// regenerate and read the PNGs after visual changes:
///
///   VISUAL_SNAPSHOTS=1 flutter test --update-goldens test/visual_snapshot_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/models/proxy_state.dart';
import 'package:singbox_client/models/subscription.dart';
import 'package:singbox_client/state/app_state.dart';
import 'package:singbox_client/ui/clock.dart';
import 'package:singbox_client/ui/theme.dart' show AppFonts;

import 'widget_test.dart' show FakeProxyController;

final _run = Platform.environment['VISUAL_SNAPSHOTS'] == '1';

/// The instant every snapshot renders at.
///
/// Four strings on these screens are derived from "now": the greeting, the
/// uptime line, and the subscription's "updated N ago" / "N days left". Left on
/// the real clock, six of the eleven goldens went red the next morning on a run
/// that had changed nothing — the greeting had turned over from evening to
/// morning and the subscription had aged a day. Evening, so the greeting branch
/// under test is the one the design was reviewed against.
final _pinnedNow = DateTime(2026, 8, 29, 21, 30);

/// Real font faces so the snapshots show the shipped typography instead of the
/// test font. Same names as pubspec.yaml declares.
Future<void> _loadFonts() async {
  Future<void> add(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(bytes.buffer.asByteData()));
    await loader.load();
  }

  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '/home/cola/flutter';
  await add('Inter', 'assets/fonts/Inter.ttf');
  await add('SpaceGrotesk', 'assets/fonts/SpaceGrotesk.ttf');
  await add('JetBrainsMono', 'assets/fonts/JetBrainsMono-Regular.ttf');
  await add('JetBrainsMono', 'assets/fonts/JetBrainsMono-Medium.ttf');
  await add(
    'MaterialIcons',
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );

  // AppFonts.cjkFallback names system faces, and flutter_test resolves nothing
  // it was not handed explicitly — so without this the Chinese snapshot renders
  // every han glyph as tofu and proves nothing about the fallback it exists to
  // check. Registered under the chain's first family so the lookup that ships
  // is the one exercised here.
  //
  // Path is machine-specific, so a miss degrades to tofu rather than failing
  // the run; _cjkLoaded records which happened for the snapshot test to assert.
  for (final path in _cjkCandidates) {
    if (!File(path).existsSync()) continue;
    try {
      await add(AppFonts.cjkFallback.first, path);
      _cjkLoaded = true;
      break;
    } on Object {
      // Unreadable or an unsupported container; try the next candidate.
    }
  }
}

/// Whether [_loadFonts] found a CJK face to register.
bool _cjkLoaded = false;

const _cjkCandidates = <String>[
  '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
  '/System/Library/Fonts/PingFang.ttc',
];

List<ProxyNode> _nodes() {
  ProxyNode n(
    String id,
    String name,
    NodeProtocol p,
    int? latency, {
    bool fav = false,
  }) =>
      ProxyNode(
        id: id,
        name: name,
        protocol: p,
        server: '$id.example.net',
        serverPort: 443,
        latencyMs: latency,
        favorite: fav,
      );
  return [
    n('tokyo', 'Tokyo · Fast 01', NodeProtocol.vless, 42, fav: true),
    n('sg', 'Singapore · Premium 02', NodeProtocol.shadowsocks, 68),
    n('la', 'Los Angeles · Edge', NodeProtocol.trojan, 148),
    n('hk', 'Hong Kong · Backup', NodeProtocol.vmess, 218),
    n('london', 'London · Standard', NodeProtocol.vless, null),
  ];
}

/// Log lines covering every branch of the logs page's level tinting.
///
/// Real sing-box output, including the `+0800`-style level prefixes it emits,
/// so the mono column widths and the danger/amber/muted split are exercised as
/// they will be in the field rather than on invented strings.
const _logLines = <String>[
  'INFO router: loaded 4 rule-set items',
  'INFO inbound/tun[tun-in]: started at tun0',
  'INFO outbound/vless[tokyo-fast-01]: outbound connection to sub.example.net',
  'WARN dns: DNS server ns-remote returned SERVFAIL, falling back',
  'INFO dns/https[remote]: resolved cdn.example.com in 24ms',
  'ERROR outbound/trojan[la-edge]: dial tcp 203.0.113.7:443: i/o timeout',
  'INFO router: default outbound selected: tokyo-fast-01',
  'INFO inbound/tun[tun-in]: connection to 140.82.121.4:443 via proxy',
  'WARN clash-api: request from 127.0.0.1 rejected: bad token',
  'INFO outbound/vless[tokyo-fast-01]: uTLS handshake complete',
  'INFO router: rule matched: geosite-ads -> block',
  'INFO inbound/tun[tun-in]: connection to 8.8.8.8:53 hijacked to dns',
];

Future<({AppState state, FakeProxyController controller})> _harness({
  bool connected = false,
  bool logs = false,
  AppSettings settings = const AppSettings(themeMode: AppThemeMode.dark),
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  final nodes = _nodes();
  await storage.writeNodes(nodes);
  await storage.writeSelectedNodeId(nodes.first.id);
  await storage.writeSubscriptions([
    Subscription(
      id: 'sub1',
      name: 'Global Pro',
      kind: SubscriptionKind.remote,
      url: 'https://sub.example.net/get',
      nodeCount: nodes.length,
      updatedAt: DateTime(2026, 8, 20),
      expiresAt: DateTime(2026, 12, 31),
    ),
  ]);
  await storage.writeSettings(settings);
  final controller = FakeProxyController();
  final state = AppState(storage: storage, controller: controller);
  if (connected) {
    controller.emit(ProxyState(
      stage: ProxyStage.connected,
      since: _pinnedNow.subtract(const Duration(hours: 4, minutes: 12)),
    ));
    // Enough samples for a shaped sparkline: a slow build, a peak, a dip.
    const shape = [
      20, 30, 26, 40, 55, 48, 70, 90, 120, 100, 85, 110, 140, //
      125, 90, 60, 80, 110, 130, 100, 70, 50, 45, 60, 40,
    ];
    for (final i in shape) {
      controller.emitTraffic(ProxyTraffic(
        downlink: i * 65536,
        uplink: i * 9102,
        downlinkTotal: 4526587904,
        uplinkTotal: 1181116006,
        connectionsIn: 12,
        connectionsOut: 96,
        memory: 83886080,
      ));
    }
  }
  if (logs) {
    // Fixed clock, not `now`: the page renders each entry's hh:mm:ss, so a
    // wall-clock default would make this golden differ on every run.
    final at = DateTime(2026, 8, 29, 21, 4, 7);
    for (var i = 0; i < _logLines.length; i++) {
      controller.emitLog(_logLines[i], at: at.add(Duration(seconds: i * 3)));
    }
  }
  return (state: state, controller: controller);
}

/// Scrolls the page's list to its end and settles.
///
/// Both pages this is used on scroll far enough that their last rows never
/// appeared in a golden. Driving the position directly rather than dragging: a
/// fling would need a distance guess per page, and overscroll physics would
/// leave the resting offset dependent on timing.
Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable);
  // The wide layout nests scrollables (a row of panels inside the page), so
  // take the outermost — the one that owns the page's own extent.
  final position = tester.state<ScrollableState>(scrollable.first).position;
  // Jump until the extent stops growing. A sliver list only measures the
  // children it has built, so the first read understates the true end — on the
  // settings page it reported 953 against an actual 1038, leaving the last row
  // below the fold in a golden that exists to show it. Each jump builds more.
  for (var i = 0; i < 10; i++) {
    final target = position.maxScrollExtent;
    position.jumpTo(target);
    await tester.pump();
    if (position.maxScrollExtent == target) break;
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  required Size size,
  required bool connected,
  bool logs = false,
  AppSettings settings = const AppSettings(themeMode: AppThemeMode.dark),
  Future<void> Function()? navigate,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  pinClock(_pinnedNow);
  addTearDown(resetClock);

  final harness = await _harness(
    connected: connected,
    logs: logs,
    settings: settings,
  );
  addTearDown(harness.state.dispose);
  await tester.pumpWidget(SingBoxApp(state: harness.state));
  await tester.pump(const Duration(milliseconds: 300));
  await navigate?.call();
  await tester.pump(const Duration(milliseconds: 400));

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('snapshots/$name.png'),
  );
}

void main() {
  setUpAll(_loadFonts);

  group(
    'visual snapshots',
    skip: !_run,
    () {
      testWidgets(
        'home / disconnected / mobile',
        (tester) => _shot(
          tester,
          'home_disconnected_mobile',
          size: const Size(390, 844),
          connected: false,
        ),
      );
      testWidgets(
        'home / connected / mobile',
        (tester) => _shot(
          tester,
          'home_connected_mobile',
          size: const Size(390, 844),
          connected: true,
        ),
      );
      testWidgets(
        'home / connected / desktop',
        (tester) => _shot(
          tester,
          'home_connected_desktop',
          size: const Size(1440, 900),
          connected: true,
        ),
      );
      // The other three dimensions of the render matrix are asserted only as
      // "renders without throwing", which cannot see a colour. These two put
      // pixels on the non-default axes: light mode, where the foreground
      // accents are re-picked rather than inverted and the dial's mint label on
      // its own tinted disc is the tightest pairing in the palette; and
      // Chinese, where the display and mono faces carry no CJK and every glyph
      // comes from the fallback chain.
      testWidgets(
        'home / connected / mobile / light',
        (tester) => _shot(
          tester,
          'home_connected_mobile_light',
          size: const Size(390, 844),
          connected: true,
          settings: const AppSettings(themeMode: AppThemeMode.light),
        ),
      );
      testWidgets(
        'home / connected / mobile / chinese',
        (tester) async {
          // This shot exists to show han glyphs resolving through
          // AppFonts.cjkFallback. If no CJK face was registered, every one of
          // them rasterizes as tofu and the golden looks plausible while
          // proving nothing — so fail loudly instead of banking the blanks.
          expect(
            _cjkLoaded,
            isTrue,
            reason: 'no CJK face found in _cjkCandidates; add this machine\'s '
                'path there, or the Chinese snapshot is all tofu',
          );
          await _shot(
            tester,
            'home_connected_mobile_zh',
            size: const Size(390, 844),
            connected: true,
            settings: const AppSettings(
              themeMode: AppThemeMode.dark,
              language: AppLanguage.chinese,
            ),
          );
        },
      );
      testWidgets(
        'nodes / mobile',
        (tester) => _shot(
          tester,
          'nodes_mobile',
          size: const Size(390, 844),
          connected: false,
          navigate: () async {
            await tester.tap(find.byIcon(Icons.hub_outlined));
            await tester.pump();
          },
        ),
      );
      // Rules and logs were the two screens with no pixel coverage at all.
      // Rules carries the segmented control and the per-rule action badges;
      // logs carries the only mono-on-panel body text in the app, and its three
      // severity tints (muted / amber / danger) are picked by substring match on
      // the engine's own words — a branch no golden had ever exercised.
      testWidgets(
        'rules / mobile',
        (tester) => _shot(
          tester,
          'rules_mobile',
          size: const Size(390, 844),
          connected: false,
          navigate: () async {
            await tester.tap(find.byIcon(Icons.alt_route_outlined));
            await tester.pump();
          },
        ),
      );
      testWidgets(
        'logs / mobile',
        (tester) => _shot(
          tester,
          'logs_mobile',
          size: const Size(390, 844),
          connected: true,
          logs: true,
          navigate: () async {
            await tester.tap(find.byIcon(Icons.receipt_long_outlined));
            await tester.pump();
          },
        ),
      );
      testWidgets(
        'settings / mobile',
        (tester) => _shot(
          tester,
          'settings_mobile',
          size: const Size(390, 844),
          connected: false,
          navigate: () async {
            await tester.tap(find.byIcon(Icons.settings_outlined));
            await tester.pump();
          },
        ),
      );
      // The shot above stops well short of the page end, so the About row —
      // and the version string on it — has never been in a golden. Scrolled to
      // the bottom so the last rows get the same pixel coverage as the first.
      testWidgets(
        'settings / mobile / bottom',
        (tester) => _shot(
          tester,
          'settings_mobile_bottom',
          size: const Size(390, 844),
          connected: false,
          navigate: () async {
            await tester.tap(find.byIcon(Icons.settings_outlined));
            await tester.pump();
            await _scrollToEnd(tester);
          },
        ),
      );
      // Same gap on the wide layout: at 900px tall the TRAFFIC FLOW panel is
      // cut off mid-chart, so its lower half and "Last 60s" caption were only
      // ever confirmed by reading the code.
      testWidgets(
        'home / connected / desktop / bottom',
        (tester) => _shot(
          tester,
          'home_connected_desktop_bottom',
          size: const Size(1440, 900),
          connected: true,
          navigate: () async => _scrollToEnd(tester),
        ),
      );
    },
  );
}
