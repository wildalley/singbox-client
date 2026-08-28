/// Renders a sing-box 1.13 configuration from app state.
///
/// The output shape follows the 1.12+ schema: typed DNS servers, rule `action`
/// verbs instead of `block`/`dns-out` outbounds, and a single `address` list on
/// the TUN inbound.
library;

import 'dart:convert';

import '../models/app_settings.dart';
import '../models/node.dart';

/// Outbound tags referenced by generated route rules.
class ConfigTags {
  static const proxy = 'proxy';
  static const direct = 'direct';
  static const auto = 'auto';
}

class ConfigBuilder {
  const ConfigBuilder._();

  /// Local Clash API port, also used to read traffic when the platform layer
  /// cannot provide it.
  static const clashApiPort = 9291;

  /// Builds the full configuration.
  ///
  /// [nodes] become individual outbounds plus a `selector`; [selectedNodeId]
  /// is the selector default. When [nodes] is empty the proxy selector falls
  /// back to direct so the service can still start.
  static Map<String, dynamic> build({
    required List<ProxyNode> nodes,
    required String? selectedNodeId,
    required AppSettings settings,
  }) {
    final nodeTags = <String, String>{};
    final outbounds = <Map<String, dynamic>>[];

    for (final node in nodes) {
      final tag = outboundTag(node);
      nodeTags[node.id] = tag;
      outbounds.add(node.toOutbound(tag));
    }

    final proxyMembers = nodeTags.values.toList();

    if (proxyMembers.isEmpty) {
      outbounds.add({
        'type': 'selector',
        'tag': ConfigTags.proxy,
        'outbounds': [ConfigTags.direct],
        'default': ConfigTags.direct,
      });
    } else {
      outbounds.add({
        'type': 'urltest',
        'tag': ConfigTags.auto,
        'outbounds': proxyMembers,
        'url': 'https://www.gstatic.com/generate_204',
        'interval': '3m',
        'tolerance': 50,
      });
      final defaultTag = selectedNodeId != null && nodeTags[selectedNodeId] != null
          ? nodeTags[selectedNodeId]!
          : ConfigTags.auto;
      outbounds.add({
        'type': 'selector',
        'tag': ConfigTags.proxy,
        'outbounds': [ConfigTags.auto, ...proxyMembers],
        'default': defaultTag,
        'interrupt_exist_connections': false,
      });
    }

    outbounds.add({'type': 'direct', 'tag': ConfigTags.direct});

    return {
      'log': {
        'level': settings.logLevel.name,
        'timestamp': false,
      },
      'dns': _dns(settings),
      'inbounds': _inbounds(settings),
      'outbounds': outbounds,
      'route': _route(settings),
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:$clashApiPort',
        },
        'cache_file': {
          'enabled': true,
          'store_fakeip': settings.fakeIp,
        },
      },
    };
  }

  static Map<String, dynamic> _dns(AppSettings settings) {
    final servers = <Map<String, dynamic>>[
      // Proxied lookups: resolved on the far side so results match the exit.
      {
        'type': settings.remoteDnsType,
        'tag': 'dns-remote',
        'server': settings.remoteDnsHost,
        if (settings.remoteDnsPath.isNotEmpty) 'path': settings.remoteDnsPath,
        'detour': ConfigTags.proxy,
      },
      // Direct lookups for domains routed around the proxy.
      {
        'type': settings.directDnsType,
        'tag': 'dns-direct',
        'server': settings.directDnsHost,
        if (settings.directDnsPath.isNotEmpty) 'path': settings.directDnsPath,
        'detour': ConfigTags.direct,
      },
      // System resolver, used to bootstrap the servers above.
      {
        'type': 'local',
        'tag': 'dns-local',
      },
    ];

    final rules = <Map<String, dynamic>>[
      {
        'rule_set': ['geosite-cn'],
        'server': 'dns-direct',
      },
      {
        'clash_mode': 'Direct',
        'server': 'dns-direct',
      },
      {
        'clash_mode': 'Global',
        'server': 'dns-remote',
      },
    ];

    if (settings.blockAds) {
      rules.insert(0, {
        'rule_set': ['geosite-ads'],
        'action': 'reject',
      });
    }

    if (settings.fakeIp) {
      servers.add({
        'type': 'fakeip',
        'tag': 'dns-fakeip',
        'inet4_range': '198.18.0.0/15',
        if (settings.ipv6) 'inet6_range': 'fc00::/18',
      });
      // FakeIP only answers A/AAAA; everything else falls through to `final`.
      rules.add({
        'query_type': settings.ipv6 ? ['A', 'AAAA'] : ['A'],
        'server': 'dns-fakeip',
      });
    }

    return {
      'servers': servers,
      'rules': rules,
      'final': 'dns-remote',
      'strategy': settings.ipv6 ? 'prefer_ipv4' : 'ipv4_only',
      'independent_cache': true,
    };
  }

  static List<Map<String, dynamic>> _inbounds(AppSettings settings) {
    return [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'address': [
          '172.19.0.1/30',
          if (settings.ipv6) 'fdfe:dcba:9876::1/126',
        ],
        'mtu': settings.mtu,
        'auto_route': true,
        'strict_route': settings.strictRoute,
        'stack': settings.tunStack.tag,
        'endpoint_independent_nat': true,
        if (settings.systemProxy)
          'platform': {
            'http_proxy': {
              'enabled': true,
              'server': '127.0.0.1',
              'server_port': 2080,
            },
          },
      },
    ];
  }

  static Map<String, dynamic> _route(AppSettings settings) {
    final rules = <Map<String, dynamic>>[
      // Sniff first so domain rules can match on TLS/HTTP hostnames.
      {'action': 'sniff'},
      // Send DNS queries to the internal resolver.
      {'protocol': 'dns', 'action': 'hijack-dns'},
      // Never route LAN traffic through the proxy.
      if (settings.bypassLan)
        {'ip_is_private': true, 'outbound': ConfigTags.direct},
      {'clash_mode': 'Direct', 'outbound': ConfigTags.direct},
      {'clash_mode': 'Global', 'outbound': ConfigTags.proxy},
    ];

    final ruleSets = <Map<String, dynamic>>[
      _remoteRuleSet('geosite-cn', 'geosite', 'geolocation-cn'),
      _remoteRuleSet('geoip-cn', 'geoip', 'cn'),
    ];

    if (settings.blockAds) {
      ruleSets.add(_remoteRuleSet('geosite-ads', 'geosite', 'category-ads-all'));
      rules.add({
        'rule_set': ['geosite-ads'],
        'action': 'reject',
      });
    }

    if (settings.routingMode == RoutingMode.rule) {
      rules.add({
        'rule_set': ['geosite-cn', 'geoip-cn'],
        'outbound': ConfigTags.direct,
      });
    }

    return {
      'rules': rules,
      'rule_set': ruleSets,
      'final': switch (settings.routingMode) {
        RoutingMode.global => ConfigTags.proxy,
        RoutingMode.direct => ConfigTags.direct,
        RoutingMode.rule => ConfigTags.proxy,
      },
      'auto_detect_interface': true,
      'default_domain_resolver': {
        'server': 'dns-local',
      },
    };
  }

  static Map<String, dynamic> _remoteRuleSet(
      String tag, String kind, String name) {
    return {
      'type': 'remote',
      'tag': tag,
      'format': 'binary',
      'url':
          'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/$kind-$name.srs',
      'download_detour': ConfigTags.direct,
      'update_interval': '7d',
    };
  }

  /// The outbound tag for [node].
  ///
  /// Both [build] and the runtime `selectOutbound` call must agree on this, so
  /// it lives in one place. The id suffix keeps tags unique when two nodes
  /// share a name.
  static String outboundTag(ProxyNode node) =>
      '${_sanitizeTag(node.name)}-${node.id}';

  /// sing-box tags allow most characters but spaces and quotes make configs
  /// hard to read and break some panels, so keep them conservative.
  static String _sanitizeTag(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[^\w一-龥.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (cleaned.isEmpty) return 'node';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  static String encode(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);
}
