import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/models/node.dart';

ProxyNode _node({
  String id = 'n1',
  String name = 'Tokyo · Fast 01',
  NodeProtocol protocol = NodeProtocol.trojan,
  String server = 'example.com',
  int port = 443,
}) {
  return ProxyNode(
    id: id,
    name: name,
    protocol: protocol,
    server: server,
    serverPort: port,
    raw: const {'password': 'secret'},
  );
}

/// Finds an outbound by tag.
Map<String, dynamic>? _outbound(Map<String, dynamic> config, String tag) {
  for (final item in config['outbounds'] as List) {
    final map = Map<String, dynamic>.from(item as Map);
    if (map['tag'] == tag) return map;
  }
  return null;
}

/// [ConfigBuilder.build] with a stand-in Clash API secret.
///
/// The real one is required so that no production path can render a config
/// without it; every case below is about something else, so the value lives here
/// once instead of on thirty call sites.
Map<String, dynamic> _build({
  required List<ProxyNode> nodes,
  required String? selectedNodeId,
  required AppSettings settings,
  String? ruleSetDir,
  String clashSecret = 'test-secret',
}) =>
    ConfigBuilder.build(
      nodes: nodes,
      selectedNodeId: selectedNodeId,
      settings: settings,
      clashSecret: clashSecret,
      ruleSetDir: ruleSetDir,
    );

void main() {
  group('outbounds', () {
    test('renders one outbound per node plus auto, selector, and direct', () {
      final config = _build(
        nodes: [_node(id: 'a', name: 'A'), _node(id: 'b', name: 'B')],
        selectedNodeId: 'b',
        settings: const AppSettings(),
      );

      final tags = (config['outbounds'] as List)
          .map((item) => (item as Map)['tag'] as String)
          .toList();

      expect(tags, hasLength(5));
      expect(tags, contains(ConfigTags.auto));
      expect(tags, contains(ConfigTags.proxy));
      expect(tags, contains(ConfigTags.direct));
    });

    test('the selector defaults to the selected node', () {
      final nodes = [_node(id: 'a', name: 'A'), _node(id: 'b', name: 'B')];
      final config = _build(
        nodes: nodes,
        selectedNodeId: 'b',
        settings: const AppSettings(),
      );

      final selector = _outbound(config, ConfigTags.proxy)!;
      expect(selector['default'], ConfigBuilder.outboundTag(nodes[1]));
    });

    test('an unknown selection falls back to auto', () {
      final config = _build(
        nodes: [_node(id: 'a')],
        selectedNodeId: 'missing',
        settings: const AppSettings(),
      );

      expect(_outbound(config, ConfigTags.proxy)!['default'], ConfigTags.auto);
    });

    test('with no nodes the selector points at direct so start still works',
        () {
      final config = _build(
        nodes: const [],
        selectedNodeId: null,
        settings: const AppSettings(),
      );

      final selector = _outbound(config, ConfigTags.proxy)!;
      expect(selector['default'], ConfigTags.direct);
      expect(_outbound(config, ConfigTags.auto), isNull);
    });

    test('outboundTag matches the tag used in the rendered config', () {
      final node = _node(name: 'Tokyo · Fast 01');
      final config = _build(
        nodes: [node],
        selectedNodeId: node.id,
        settings: const AppSettings(),
      );

      final tag = ConfigBuilder.outboundTag(node);
      expect(_outbound(config, tag), isNotNull);
      expect(tag, contains(node.id));
    });

    test('tags stay unique when two nodes share a name', () {
      final nodes = [
        _node(id: 'a', name: 'Same Name'),
        _node(id: 'b', name: 'Same Name'),
      ];
      final config = _build(
        nodes: nodes,
        selectedNodeId: 'a',
        settings: const AppSettings(),
      );

      final tags = (config['outbounds'] as List)
          .map((item) => (item as Map)['tag'] as String)
          .toSet();
      expect(tags.length, 5);
    });

    test('node credentials survive into the outbound', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(),
      );

      final tag = ConfigBuilder.outboundTag(_node());
      expect(_outbound(config, tag)!['password'], 'secret');
    });
  });

  group('routing', () {
    test('rule mode sends CN traffic direct and keeps proxy as final', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(routingMode: RoutingMode.rule),
      );

      final route = config['route'] as Map<String, dynamic>;
      expect(route['final'], ConfigTags.proxy);

      final hasCnDirect = (route['rules'] as List).any((item) {
        final rule = Map<String, dynamic>.from(item as Map);
        final ruleSet = rule['rule_set'];
        return ruleSet is List &&
            ruleSet.contains('geoip-cn') &&
            rule['outbound'] == ConfigTags.direct;
      });
      expect(hasCnDirect, isTrue);
    });

    test('global mode does not add the CN direct rule', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(routingMode: RoutingMode.global),
      );

      final route = config['route'] as Map<String, dynamic>;
      expect(route['final'], ConfigTags.proxy);

      final hasCnDirect = (route['rules'] as List).any((item) {
        final ruleSet = (item as Map)['rule_set'];
        return ruleSet is List && ruleSet.contains('geoip-cn');
      });
      expect(hasCnDirect, isFalse);
    });

    test('direct mode routes everything direct', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(routingMode: RoutingMode.direct),
      );

      expect((config['route'] as Map)['final'], ConfigTags.direct);
    });

    test('sniff runs before the DNS hijack', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(),
      );

      final rules = (config['route'] as Map)['rules'] as List;
      final sniffIndex =
          rules.indexWhere((item) => (item as Map)['action'] == 'sniff');
      final hijackIndex =
          rules.indexWhere((item) => (item as Map)['action'] == 'hijack-dns');

      expect(sniffIndex, isNonNegative);
      expect(hijackIndex, greaterThan(sniffIndex));
    });

    test('ad blocking adds a reject rule and its rule set', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(blockAds: true),
      );

      final route = config['route'] as Map<String, dynamic>;
      final hasReject = (route['rules'] as List).any(
        (item) => (item as Map)['action'] == 'reject',
      );
      final hasRuleSet = (route['rule_set'] as List).any(
        (item) => (item as Map)['tag'] == 'geosite-ads',
      );

      expect(hasReject, isTrue);
      expect(hasRuleSet, isTrue);
    });

    test('disabling ad blocking removes both', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(blockAds: false),
      );

      final route = config['route'] as Map<String, dynamic>;
      expect(
        (route['rules'] as List)
            .any((item) => (item as Map)['action'] == 'reject'),
        isFalse,
      );
      expect(
        (route['rule_set'] as List).any(
          (item) => (item as Map)['tag'] == 'geosite-ads',
        ),
        isFalse,
      );
    });
  });

  group('rule sets', () {
    /// Every rule-set declared in `route.rule_set`, by tag.
    Map<String, Map<String, dynamic>> sets(Map<String, dynamic> config) {
      final route = config['route'] as Map<String, dynamic>;
      return {
        for (final item in route['rule_set'] as List)
          (item as Map)['tag'] as String: Map<String, dynamic>.from(item),
      };
    }

    test('a rule-set directory makes them local, with no network fields', () {
      // The whole point of bundling: sing-box initializes rule-sets during
      // start and a failed fetch is fatal, so anything left reaching out here
      // can abort the tunnel.
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(blockAds: true),
        ruleSetDir: '/data/app/rule-sets',
      );

      final declared = sets(config);
      expect(declared.keys,
          containsAll(['geosite-cn', 'geoip-cn', 'geosite-ads']));
      for (final entry in declared.entries) {
        expect(entry.value['type'], 'local');
        expect(entry.value['format'], 'binary');
        expect(entry.value['path'], '/data/app/rule-sets/${entry.key}.srs');
        expect(entry.value.keys,
            isNot(anyOf(contains('url'), contains('download_detour'))));
      }
    });

    test('without one they fall back to remote, each from its own repository',
        () {
      // geoip and geosite are separate repositories. geoip-cn under
      // sing-geosite is a 404, which surfaces on the device as a rule-set
      // download failure and reads like a network problem.
      final declared = sets(_build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(),
      ));

      expect(declared['geosite-cn']!['type'], 'remote');
      expect(declared['geosite-cn']!['url'],
          endsWith('sing-geosite/rule-set/geosite-geolocation-cn.srs'));
      expect(declared['geoip-cn']!['url'],
          endsWith('sing-geoip/rule-set/geoip-cn.srs'));
    });

    test('every referenced tag is declared, in both modes', () {
      // A rule naming a rule-set that is not declared fails the whole start.
      for (final dir in [null, '/data/app/rule-sets']) {
        final config = _build(
          nodes: [_node()],
          selectedNodeId: 'n1',
          settings: const AppSettings(blockAds: true),
          ruleSetDir: dir,
        );
        final declared = sets(config).keys.toSet();
        final referenced = <String>{
          for (final section in [config['dns'], config['route']])
            for (final rule in (section as Map)['rules'] as List)
              ...?((rule as Map)['rule_set'] as List?)?.cast<String>(),
        };

        expect(referenced, isNotEmpty);
        expect(declared, containsAll(referenced), reason: 'ruleSetDir: $dir');
      }
    });
  });

  group('tun inbound', () {
    test('applies mtu, stack, and strict route from settings', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(
          mtu: 1500,
          tunStack: TunStack.gvisor,
          strictRoute: true,
        ),
      );

      final tun = Map<String, dynamic>.from((config['inbounds'] as List).first);
      expect(tun['mtu'], 1500);
      expect(tun['stack'], 'gvisor');
      expect(tun['strict_route'], true);
    });

    test('ipv6 adds a second tun address', () {
      final v4 = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(ipv6: false),
      );
      final v6 = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(ipv6: true),
      );

      expect(((v4['inbounds'] as List).first as Map)['address'], hasLength(1));
      expect(((v6['inbounds'] as List).first as Map)['address'], hasLength(2));
    });

    test('system proxy adds the platform http proxy block', () {
      final off = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(systemProxy: false),
      );
      final on = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(systemProxy: true),
      );

      expect(((off['inbounds'] as List).first as Map)['platform'], isNull);
      expect(((on['inbounds'] as List).first as Map)['platform'], isNotNull);
    });

    test('the advertised system proxy is the port something listens on', () {
      // The tun's platform block promises an address; the mixed inbound is what
      // makes it answer. A literal on either side breaks every app that honours
      // the system proxy setting, and only on a device.
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(systemProxy: true),
      );

      final inbounds = config['inbounds'] as List;
      final tun = inbounds.first as Map;
      final mixed = inbounds.firstWhere((item) => (item as Map)['type'] == 'mixed') as Map;

      expect(tun['type'], 'tun', reason: 'the tests read the tun as inbounds[0]');
      expect(mixed['listen'], '127.0.0.1',
          reason: 'the sing-box default would expose an open proxy to the LAN');
      expect(mixed['listen_port'], ConfigBuilder.localProxyPort);
      expect(
        (((tun['platform'] as Map)['http_proxy'] as Map))['server_port'],
        mixed['listen_port'],
      );
    });

    test('the loopback proxy is there even with the system proxy off', () {
      // The rule-set update goes out through it: the app's own package is
      // excluded from the VPN, so this is the only path from in-app HTTP to the
      // selected node.
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(systemProxy: false),
      );

      expect(
        (config['inbounds'] as List).where((item) => (item as Map)['type'] == 'mixed'),
        hasLength(1),
      );
    });
  });

  group('dns', () {
    test('derives the server type and host from the configured URL', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(dnsRemote: 'tls://9.9.9.9'),
      );

      final servers = (config['dns'] as Map)['servers'] as List;
      final remote = servers
          .map((item) => Map<String, dynamic>.from(item as Map))
          .firstWhere((item) => item['tag'] == 'dns-remote');

      expect(remote['type'], 'tls');
      expect(remote['server'], '9.9.9.9');
      // Remote lookups must resolve on the far side of the tunnel.
      expect(remote['detour'], ConfigTags.proxy);
    });

    test('the direct server carries no detour', () {
      // sing-box counts a `direct` outbound with no dialer options as empty and
      // refuses to start a DNS server that detours to it: "detour to an empty
      // direct outbound makes no sense". A DNS server already dials directly.
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(),
      );

      final direct = ((config['dns'] as Map)['servers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .firstWhere((item) => item['tag'] == 'dns-direct');

      expect(direct.containsKey('detour'), isFalse);
    });

    test('an IP direct server needs no domain resolver', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(dnsDirect: 'https://223.5.5.5/dns-query'),
      );

      final direct = ((config['dns'] as Map)['servers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .firstWhere((item) => item['tag'] == 'dns-direct');

      expect(direct.containsKey('domain_resolver'), isFalse);
    });

    test('a hostname direct server names its own resolver', () {
      // Without a detour the resolve path is live, and a DNS server does not
      // fall back to route.default_domain_resolver, so start would fail with
      // "missing domain resolver for domain server address".
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings:
            const AppSettings(dnsDirect: 'https://dns.alidns.com/dns-query'),
      );

      final direct = ((config['dns'] as Map)['servers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .firstWhere((item) => item['tag'] == 'dns-direct');

      expect(direct['server'], 'dns.alidns.com');
      expect((direct['domain_resolver'] as Map)['server'], 'dns-bootstrap');
    });

    test('the bootstrap resolver is plain UDP at an IP literal', () {
      // The one lookup path that runs before the tunnel exists. It used to be
      // `{'type': 'local'}`, which delegates to PlatformInterface — and our
      // Android localDNSTransport() returns null, so libbox fell back to Go
      // reading /etc/resolv.conf, found no nameserver, and sent every startup
      // query to loopback: "read udp [::1]:53: connection refused".
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(),
      );

      final servers = ((config['dns'] as Map)['servers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final bootstrap =
          servers.firstWhere((item) => item['tag'] == 'dns-bootstrap');

      expect(bootstrap['type'], 'udp');
      expect(InternetAddress.tryParse(bootstrap['server'] as String),
          isNotNull);
      expect(bootstrap.containsKey('detour'), isFalse,
          reason: 'must reach the network without the tunnel');
      expect(servers.any((item) => item['type'] == 'local'), isFalse,
          reason: 'type: local needs a platform transport we do not provide');
    });

    test('the bootstrap resolver reuses an IP direct DNS host', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(dnsDirect: 'udp://119.29.29.29'),
      );

      final bootstrap = ((config['dns'] as Map)['servers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .firstWhere((item) => item['tag'] == 'dns-bootstrap');

      expect(bootstrap['server'], '119.29.29.29');
    });

    test('a hostname direct DNS host does not become the bootstrap', () {
      // Resolving that hostname is the very job the bootstrap server exists to
      // do, so it has to fall back to a literal.
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings:
            const AppSettings(dnsDirect: 'https://dns.alidns.com/dns-query'),
      );

      final bootstrap = ((config['dns'] as Map)['servers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .firstWhere((item) => item['tag'] == 'dns-bootstrap');

      expect(InternetAddress.tryParse(bootstrap['server'] as String),
          isNotNull);
    });

    test('fakeip adds its server and is reflected in the cache file', () {
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(fakeIp: true),
      );

      final servers = (config['dns'] as Map)['servers'] as List;
      expect(
        servers.any((item) => (item as Map)['type'] == 'fakeip'),
        isTrue,
      );
      expect(
        ((config['experimental'] as Map)['cache_file'] as Map)['store_fakeip'],
        isTrue,
      );
    });
  });

  group('clash api', () {
    Map<String, dynamic> clashApi(Map<String, dynamic> config) =>
        Map<String, dynamic>.from(
          (config['experimental'] as Map)['clash_api'] as Map,
        );

    test('the listener stays on loopback and carries the secret', () {
      // On Android 127.0.0.1 is reachable by every app on the device, so the
      // listen address is not a boundary — the token is the only one there is.
      final config = _build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(),
        clashSecret: 'deadbeef',
      );

      final api = clashApi(config);
      expect(api['external_controller'], '127.0.0.1:${ConfigBuilder.clashApiPort}');
      expect(api['secret'], 'deadbeef');
    });

    test('the secret is rendered even with no nodes', () {
      // Nothing about the listener depends on nodes, but the same function
      // renders both and the empty-node branch is the less travelled one.
      final config = _build(
        nodes: const [],
        selectedNodeId: null,
        settings: const AppSettings(),
      );

      expect(clashApi(config)['secret'], 'test-secret');
    });
  });

  test('log level comes from settings', () {
    final config = _build(
      nodes: [_node()],
      selectedNodeId: 'n1',
      settings: const AppSettings(logLevel: LogLevel.debug),
    );

    expect((config['log'] as Map)['level'], 'debug');
  });

  test('encode produces valid JSON that round-trips', () {
    final config = _build(
      nodes: [_node()],
      selectedNodeId: 'n1',
      settings: const AppSettings(),
    );

    final decoded = jsonDecode(ConfigBuilder.encode(config));
    expect(decoded, isA<Map<String, dynamic>>());
    expect((decoded as Map)['outbounds'], isA<List>());
  });
}
