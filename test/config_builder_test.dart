import 'dart:convert';

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

void main() {
  group('outbounds', () {
    test('renders one outbound per node plus auto, selector, and direct', () {
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
        nodes: nodes,
        selectedNodeId: 'b',
        settings: const AppSettings(),
      );

      final selector = _outbound(config, ConfigTags.proxy)!;
      expect(selector['default'], ConfigBuilder.outboundTag(nodes[1]));
    });

    test('an unknown selection falls back to auto', () {
      final config = ConfigBuilder.build(
        nodes: [_node(id: 'a')],
        selectedNodeId: 'missing',
        settings: const AppSettings(),
      );

      expect(_outbound(config, ConfigTags.proxy)!['default'], ConfigTags.auto);
    });

    test('with no nodes the selector points at direct so start still works',
        () {
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(routingMode: RoutingMode.direct),
      );

      expect((config['route'] as Map)['final'], ConfigTags.direct);
    });

    test('sniff runs before the DNS hijack', () {
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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

  group('tun inbound', () {
    test('applies mtu, stack, and strict route from settings', () {
      final config = ConfigBuilder.build(
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
      final v4 = ConfigBuilder.build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(ipv6: false),
      );
      final v6 = ConfigBuilder.build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(ipv6: true),
      );

      expect(((v4['inbounds'] as List).first as Map)['address'], hasLength(1));
      expect(((v6['inbounds'] as List).first as Map)['address'], hasLength(2));
    });

    test('system proxy adds the platform http proxy block', () {
      final off = ConfigBuilder.build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(systemProxy: false),
      );
      final on = ConfigBuilder.build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings: const AppSettings(systemProxy: true),
      );

      expect(((off['inbounds'] as List).first as Map)['platform'], isNull);
      expect(((on['inbounds'] as List).first as Map)['platform'], isNotNull);
    });
  });

  group('dns', () {
    test('derives the server type and host from the configured URL', () {
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
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
      final config = ConfigBuilder.build(
        nodes: [_node()],
        selectedNodeId: 'n1',
        settings:
            const AppSettings(dnsDirect: 'https://dns.alidns.com/dns-query'),
      );

      final direct = ((config['dns'] as Map)['servers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .firstWhere((item) => item['tag'] == 'dns-direct');

      expect(direct['server'], 'dns.alidns.com');
      expect((direct['domain_resolver'] as Map)['server'], 'dns-local');
    });

    test('fakeip adds its server and is reflected in the cache file', () {
      final config = ConfigBuilder.build(
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

  test('log level comes from settings', () {
    final config = ConfigBuilder.build(
      nodes: [_node()],
      selectedNodeId: 'n1',
      settings: const AppSettings(logLevel: LogLevel.debug),
    );

    expect((config['log'] as Map)['level'], 'debug');
  });

  test('encode produces valid JSON that round-trips', () {
    final config = ConfigBuilder.build(
      nodes: [_node()],
      selectedNodeId: 'n1',
      settings: const AppSettings(),
    );

    final decoded = jsonDecode(ConfigBuilder.encode(config));
    expect(decoded, isA<Map<String, dynamic>>());
    expect((decoded as Map)['outbounds'], isA<List>());
  });
}
