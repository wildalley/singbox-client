/// Renders a sing-box 1.13 configuration from app state.
///
/// The output shape follows the 1.12+ schema: typed DNS servers, rule `action`
/// verbs instead of `block`/`dns-out` outbounds, and a single `address` list on
/// the TUN inbound.
library;

import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/custom_rule.dart';
import '../models/node.dart';
import 'rule_sets.dart';

/// Outbound tags referenced by generated route rules.
class ConfigTags {
  static const proxy = 'proxy';
  static const direct = 'direct';
  static const auto = 'auto';
}

class ConfigBuilder {
  const ConfigBuilder._();

  /// Local Clash API port, bound to loopback and gated behind a secret.
  ///
  /// On Android nothing in the app talks to it — libbox reaches the runtime over
  /// its own command socket — but the listener still has to exist for the
  /// clash-mode rules and the traffic figures libbox reads from it. On Linux it
  /// is the only control channel there is: the supervised `sing-box` has no
  /// command socket, so node switching, URL tests, traffic, and memory all go
  /// through this port.
  static const clashApiPort = 9291;

  /// Loopback HTTP/SOCKS inbound, on 127.0.0.1 only.
  ///
  /// Three consumers: `systemProxy` advertises this address to Android, the
  /// in-app rule-set update sends its download through it, and Linux
  /// system-proxy mode points GNOME or KDE at it. The second one is why the
  /// inbound is unconditional even in tun mode — the app's own package is
  /// excluded from the tunnel, so this is the only way anything the app fetches
  /// can leave through the selected node.
  static const localProxyPort = 2080;

  /// Builds the full configuration.
  ///
  /// [nodes] become individual outbounds plus a `selector`; [selectedNodeId]
  /// is the selector default. When [nodes] is empty the proxy selector falls
  /// back to direct so the service can still start.
  ///
  /// [ruleSetDir] is where `BundledRuleSets` unpacked the shipped `.srs` files.
  /// Given one, the rule-sets are `local` and start needs no network; without
  /// one they fall back to `remote`, which is fatal on an unreachable URL.
  ///
  /// [clashSecret] is the bearer token for the Clash API listener. Required, not
  /// defaulted: on Android every app on the device can reach 127.0.0.1, so an
  /// unauthenticated listener lets any of them switch the user's outbound and
  /// read their connection list. Nothing may render this config without one.
  ///
  /// [tunOnly] overrides the platform check that ignores
  /// [AppSettings.proxyMode] on Android. For tests only; production leaves it
  /// null.
  /// [customRules] are the user's own rules, rendered above the bundled
  /// rule-sets so a specific answer wins over a general one — see [_route].
  /// Invalid and disabled entries are skipped here rather than at the call site.
  static Map<String, dynamic> build({
    required List<ProxyNode> nodes,
    required String? selectedNodeId,
    required AppSettings settings,
    required String clashSecret,
    List<CustomRule> customRules = const [],
    String? ruleSetDir,
    bool? tunOnly,
  }) {
    // Android has one way in — VpnService hands over a tun and there is no
    // settings row to choose otherwise — so the stored mode does not apply
    // there. Injectable because the tests run on Linux and need both renders.
    final alwaysTun = tunOnly ?? Platform.isAndroid;
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
      'inbounds': _inbounds(settings, alwaysTun: alwaysTun),
      'outbounds': outbounds,
      'route': _route(settings, ruleSetDir, customRules),
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:$clashApiPort',
          'secret': clashSecret,
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

  static List<Map<String, dynamic>> _inbounds(
    AppSettings settings, {
    required bool alwaysTun,
  }) {
    final tun = alwaysTun || settings.proxyMode == ProxyMode.tun;
    return [
      // Omitted entirely in system-proxy mode: a tun inbound is the one part of
      // this config that needs a privileged interface, and nothing else refers
      // to it — no route rule matches an inbound tag, `auto_detect_interface`
      // is inert without one, and the FakeIP ranges are only ever reached
      // through a tun's DNS hijack, so they sit unused rather than misroute.
      if (tun)
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
                // The mixed inbound below is what makes this address answer; an
                // advertised proxy with nothing behind it breaks every app that
                // honours the system setting.
                'server_port': localProxyPort,
              },
            },
        },
      // Loopback proxy for traffic that cannot use the tun: the app itself is
      // excluded from the VPN, so its own requests (the rule-set update) reach
      // the tunnel only through here. Bound to 127.0.0.1 deliberately — the
      // sing-box default listen address would expose an open proxy to the LAN.
      {
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': localProxyPort,
      },
    ];
  }

  static Map<String, dynamic> _route(
    AppSettings settings,
    String? ruleSetDir,
    List<CustomRule> customRules,
  ) {
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
      _ruleSet('geosite-cn', ruleSetDir),
      _ruleSet('geoip-cn', ruleSetDir),
    ];

    // The user's own rules, above the bundled lists and below the overrides.
    //
    // sing-box takes the first rule that matches, so this position is the whole
    // behaviour. Above the ad and CN lists, because a rule someone typed for one
    // domain is a more specific answer than a list of millions and should beat
    // it. Below the clash-mode rules and the LAN bypass, because those are not
    // opinions about a destination: clash-mode is a global override the user
    // just flipped, and the LAN bypass keeps local traffic off the tunnel.
    //
    // One entry per rule, in the user's order, rather than merging rules that
    // share a matcher and target. Merging would be a smaller config, but it
    // would also reorder them — and first-match-wins means the order on screen
    // has to be the order in the config.
    rules.addAll(customRules.where((rule) => rule.enabled && rule.isValid).map(
          (rule) => {
            // Ports are uint16 in sing-box's schema, every other matcher is a
            // string list. Rendering a port as `["443"]` fails at *decode* —
            // "cannot unmarshal string into Go value of type uint16" — so the
            // whole tunnel refuses to start over one quoted number, with nothing
            // naming the rule that did it. Verified against sing-box 1.13.
            //
            // The parse cannot fail because the `where` above dropped anything
            // [CustomRule.isValid] rejected, and a port that does not parse is
            // exactly what it rejects. That filter is load-bearing, not tidiness.
            rule.matcher.field: [
              if (rule.matcher == RuleMatcher.port)
                int.parse(rule.value)
              else
                rule.value,
            ],
            switch (rule.target) {
              // reject is an action, not an outbound; the other two name a tag.
              RuleTarget.block => 'action',
              _ => 'outbound',
            }: switch (rule.target) {
              RuleTarget.proxy => ConfigTags.proxy,
              RuleTarget.direct => ConfigTags.direct,
              RuleTarget.block => 'reject',
            },
          },
        ));

    if (settings.blockAds) {
      ruleSets.add(_ruleSet('geosite-ads', ruleSetDir));
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
      // Resolves outbound server hostnames — and, when the rule-sets fall back
      // to `remote`, their download URLs too. Either way this runs at start,
      // before any tunnel exists, so it has to be the bootstrap server rather
      // than `local`.
      'default_domain_resolver': {
        'server': 'dns-bootstrap',
      },
    };
  }

  /// One entry for `route.rule_set`, local when the files are on disk.
  static Map<String, dynamic> _ruleSet(String tag, String? dir) =>
      dir == null ? _remoteRuleSet(tag) : _localRuleSet(tag, dir);

  /// A rule-set read straight off disk: no network, so it cannot fail the start.
  ///
  /// This is the path Android takes; see `lib/data/rule_sets.dart` for why
  /// downloading them is not an option here.
  static Map<String, dynamic> _localRuleSet(String tag, String dir) {
    return {
      'type': 'local',
      'tag': tag,
      'format': 'binary',
      // Through BundledRuleSets so this is the same name the unpacking writes.
      'path': '$dir/${BundledRuleSets.fileName(tag)}',
    };
  }

  /// Fallback for a platform with no unpacked rule-sets.
  ///
  /// A failed fetch here aborts the whole start — sing-box has no per-rule-set
  /// optional flag — so this is the fragile path, kept only because a missing
  /// local file leaves nowhere else to read the lists from.
  static Map<String, dynamic> _remoteRuleSet(String tag) {
    return {
      'type': 'remote',
      'tag': tag,
      'format': 'binary',
      // One table of upstream URLs, shared with the updater.
      'url': BundledRuleSets.upstreamUrl(tag).toString(),
      // Through the tunnel, not around it. These are the CN rule-sets, so the
      // user fetching them is the user who cannot reach raw.githubusercontent
      // .com directly; `direct` here fails for exactly the audience it serves.
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
