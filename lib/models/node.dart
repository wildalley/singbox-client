/// Proxy node model and the sing-box outbound rendering for each protocol.
library;

enum NodeProtocol {
  vless('vless', 'VLESS'),
  vmess('vmess', 'VMess'),
  trojan('trojan', 'Trojan'),
  shadowsocks('shadowsocks', 'Shadowsocks'),
  hysteria2('hysteria2', 'Hysteria2'),
  tuic('tuic', 'TUIC'),
  socks('socks', 'SOCKS'),
  http('http', 'HTTP'),
  anytls('anytls', 'AnyTLS'),
  wireguard('wireguard', 'WireGuard'),
  ssh('ssh', 'SSH'),
  unknown('unknown', 'Unknown');

  const NodeProtocol(this.tag, this.label);

  /// sing-box outbound `type` value.
  final String tag;

  /// Human readable label for the UI.
  final String label;

  static NodeProtocol fromTag(String? value) {
    if (value == null) return NodeProtocol.unknown;
    final normalized = value.toLowerCase();
    return NodeProtocol.values.firstWhere(
      (item) => item.tag == normalized,
      orElse: () => switch (normalized) {
        'ss' => NodeProtocol.shadowsocks,
        'hysteria' || 'hy2' => NodeProtocol.hysteria2,
        'socks5' || 'socks4' => NodeProtocol.socks,
        _ => NodeProtocol.unknown,
      },
    );
  }
}

/// A single proxy endpoint.
///
/// [raw] keeps the original sing-box outbound object when the node came from a
/// JSON config, so re-rendering never loses fields this app does not model.
class ProxyNode {
  const ProxyNode({
    required this.id,
    required this.name,
    required this.protocol,
    required this.server,
    required this.serverPort,
    this.raw = const {},
    this.latencyMs,
    this.subscriptionId,
    this.favorite = false,
  });

  final String id;
  final String name;
  final NodeProtocol protocol;
  final String server;
  final int serverPort;
  final Map<String, dynamic> raw;

  /// Last measured latency in milliseconds. `null` means untested,
  /// [unreachableLatency] means the probe failed.
  final int? latencyMs;
  final String? subscriptionId;
  final bool favorite;

  static const unreachableLatency = -1;

  bool get isUnreachable => latencyMs == unreachableLatency;
  bool get isTested => latencyMs != null;

  ProxyNode copyWith({
    String? name,
    int? latencyMs,
    bool clearLatency = false,
    bool? favorite,
    String? subscriptionId,
  }) {
    return ProxyNode(
      id: id,
      name: name ?? this.name,
      protocol: protocol,
      server: server,
      serverPort: serverPort,
      raw: raw,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
      subscriptionId: subscriptionId ?? this.subscriptionId,
      favorite: favorite ?? this.favorite,
    );
  }

  /// Renders this node as a sing-box outbound with [tag] as its outbound tag.
  Map<String, dynamic> toOutbound(String tag) {
    final outbound = <String, dynamic>{
      ...raw,
      'type': protocol.tag,
      'tag': tag,
      'server': server,
      'server_port': serverPort,
    };
    // These are app-level concepts, not sing-box fields.
    outbound.remove('_id');
    outbound.remove('_name');
    return outbound;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.tag,
        'server': server,
        'server_port': serverPort,
        'raw': raw,
        if (latencyMs != null) 'latency_ms': latencyMs,
        if (subscriptionId != null) 'subscription_id': subscriptionId,
        'favorite': favorite,
      };

  static ProxyNode fromJson(Map<String, dynamic> json) => ProxyNode(
        id: json['id'] as String,
        name: json['name'] as String,
        protocol: NodeProtocol.fromTag(json['protocol'] as String?),
        server: json['server'] as String? ?? '',
        serverPort: (json['server_port'] as num?)?.toInt() ?? 0,
        raw: Map<String, dynamic>.from(
            json['raw'] as Map? ?? const <String, dynamic>{}),
        latencyMs: (json['latency_ms'] as num?)?.toInt(),
        subscriptionId: json['subscription_id'] as String?,
        favorite: json['favorite'] as bool? ?? false,
      );

  /// Short location hint derived from the node name, used in list rows.
  String get regionHint {
    const separators = ['·', '|', '-', '—'];
    for (final separator in separators) {
      final index = name.indexOf(separator);
      if (index > 0) return name.substring(0, index).trim();
    }
    return name;
  }
}
