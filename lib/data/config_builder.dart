/// Renders a sing-box 1.13 configuration from app state.
///
/// The output shape follows the 1.12+ schema: typed DNS servers, rule `action`
/// verbs instead of `block`/`dns-out` outbounds, and a single `address` list on
/// the TUN inbound.
library;

import 'dart:convert';
import 'dart:io';

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
      final defaultTag =
          selectedNodeId != null && nodeTags[selectedNodeId] != null
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
      //
      // No `detour` here. A DNS server already dials directly by default, and
      // sing-box treats a `direct` outbound carrying no dialer options as
      // empty, then rejects the config at startup: "detour to an empty direct
      // outbound makes no sense" (common/dialer/detour.go).
      {
        'type': settings.directDnsType,
        'tag': 'dns-direct',
        'server': settings.directDnsHost,
        if (settings.directDnsPath.isNotEmpty) 'path': settings.directDnsPath,
        // Dropping the detour turns on the resolve path for this server, and a
        // DNS server never falls back to route.default_domain_resolver, so a
        // hostname (rather than an IP) has to name its resolver here or start
        // fails with "missing domain resolver for domain server address".
        if (!_isIpLiteral(settings.directDnsHost))
          'domain_resolver': {'server': 'dns-bootstrap'},
      },
      // Bootstrap resolver: the one lookup path that has to work *before* the
      // tunnel exists, so it must not depend on either.
      //
      // This was `{'type': 'local'}`, which delegates to the platform. Android
      // only answers that if PlatformInterface.localDNSTransport() is
      // implemented; ours returns null, so libbox fell back to Go's resolver
      // reading /etc/resolv.conf — a file with no usable nameserver on Android.
      // Go then defaults to loopback and every startup lookup died with
      // "read udp [::1]:53: connection refused", taking the remote rule-set
      // downloads (and therefore the whole start) with it.
      //
      // Plain UDP at an IP literal needs no resolver to be reached itself, and
      // a DNS server dials directly by default, so this works on a bare
      // network interface with no tunnel up.
      {
        'type': 'udp',
        'tag': 'dns-bootstrap',
        'server': _bootstrapDnsHost(settings),
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
      ruleSets
          .add(_remoteRuleSet('geosite-ads', 'geosite', 'category-ads-all'));
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
      // Resolves the rule-set download URLs, which happens at start before any
      // tunnel exists — so it has to be the bootstrap server, not `local`.
      'default_domain_resolver': {
        'server': 'dns-bootstrap',
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
      // Through the tunnel, not around it. These are the CN rule-sets, so the
      // user fetching them is the user who cannot reach raw.githubusercontent
      // .com directly; `direct` here fails for exactly the audience it serves.
      // The exit node can reach GitHub, and the node's own address is resolved
      // by route.default_domain_resolver (the plain-UDP bootstrap above), so
      // this does not need the rule-sets it is downloading.
      'download_detour': ConfigTags.proxy,
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

  /// Plain-UDP address for the bootstrap resolver.
  ///
  /// Reuses the direct DNS host when the user already gave an IP literal, so
  /// one setting covers both and a user behind a filtered path can redirect the
  /// bootstrap too. A DoH/DoT hostname cannot serve here — resolving it is the
  /// very thing this server exists to do — so those fall back to a public
  /// anycast address.
  static String _bootstrapDnsHost(AppSettings settings) {
    final direct = settings.directDnsHost;
    return _isIpLiteral(direct) ? direct : _fallbackBootstrapDns;
  }

  /// AliDNS: reachable from inside and outside mainland China, which is where
  /// the bundled rule-sets are aimed.
  static const _fallbackBootstrapDns = '223.5.5.5';

  /// Whether [host] is a bare IP address rather than a hostname.
  ///
  /// Decides both whether a DNS server needs its own `domain_resolver` (the IP
  /// form needs no resolution, so it must not carry one) and whether a host can
  /// serve as the bootstrap resolver.
  static bool _isIpLiteral(String host) {
    final bare = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
    return InternetAddress.tryParse(bare) != null;
  }

  static String encode(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);
}
