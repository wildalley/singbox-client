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

  /// Two-letter region code inferred from the node name, or null when the name
  /// carries no location we recognise.
  ///
  /// Nodes come from subscriptions, which never carry a structured region — the
  /// name is all there is. So this reads the name, in order of how much the
  /// signal can be trusted: a flag emoji decodes to an exact code, then a
  /// location spelled out in Chinese or in Latin letters, then a bare code
  /// token. Null is a real answer: showing nothing beats showing the wrong
  /// country, and the row falls back to a neutral icon.
  String? get regionCode => _flagRegion(name) ?? _namedRegion(name);
}

/// Decodes a flag emoji: two regional indicator symbols map to the letters of
/// the region code they render as.
String? _flagRegion(String name) {
  final runes = name.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    if (_isRegionalIndicator(runes[i]) && _isRegionalIndicator(runes[i + 1])) {
      return String.fromCharCodes([
        0x41 + runes[i] - _indicatorA,
        0x41 + runes[i + 1] - _indicatorA,
      ]);
    }
  }
  return null;
}

const _indicatorA = 0x1F1E6;

bool _isRegionalIndicator(int rune) => rune >= _indicatorA && rune <= 0x1F1FF;

String? _namedRegion(String name) {
  final lower = name.toLowerCase();

  // CJK has no word boundaries, so these match as plain substrings. The list is
  // ordered: 印度尼西亚 has to win over the 印度 it contains.
  for (final (keyword, code) in _cjkRegions) {
    if (lower.contains(keyword)) return code;
  }

  // Spelled-out names are matched against the letters alone so that separators
  // and spacing do not matter: `US-Los Angeles-01` still finds `losangeles`.
  // Everything here is at least four letters, which keeps substring matching
  // from firing on fragments of unrelated words.
  final letters = lower.replaceAll(RegExp('[^a-z]'), '');
  for (final (keyword, code) in _spelledRegions) {
    if (letters.contains(keyword)) return code;
  }

  // Bare codes have to be whole tokens: `us` as a substring also appears in
  // `russia`, which is a different country.
  for (final token in lower.split(RegExp('[^a-z]+'))) {
    final code = _codeTokens[token];
    if (code != null) return code;
  }

  return null;
}

const _cjkRegions = <(String, String)>[
  ('香港', 'HK'),
  ('澳門', 'MO'),
  ('澳门', 'MO'),
  ('臺灣', 'TW'),
  ('台灣', 'TW'),
  ('台湾', 'TW'),
  ('日本', 'JP'),
  ('東京', 'JP'),
  ('东京', 'JP'),
  ('大阪', 'JP'),
  ('韓國', 'KR'),
  ('韩国', 'KR'),
  ('首爾', 'KR'),
  ('首尔', 'KR'),
  ('新加坡', 'SG'),
  ('獅城', 'SG'),
  ('狮城', 'SG'),
  ('美國', 'US'),
  ('美国', 'US'),
  ('洛杉磯', 'US'),
  ('洛杉矶', 'US'),
  ('聖何塞', 'US'),
  ('圣何塞', 'US'),
  ('西雅圖', 'US'),
  ('西雅图', 'US'),
  ('紐約', 'US'),
  ('纽约', 'US'),
  ('達拉斯', 'US'),
  ('达拉斯', 'US'),
  ('英國', 'GB'),
  ('英国', 'GB'),
  ('倫敦', 'GB'),
  ('伦敦', 'GB'),
  ('德國', 'DE'),
  ('德国', 'DE'),
  ('法蘭克福', 'DE'),
  ('法兰克福', 'DE'),
  ('法國', 'FR'),
  ('法国', 'FR'),
  ('巴黎', 'FR'),
  ('荷蘭', 'NL'),
  ('荷兰', 'NL'),
  ('阿姆斯特丹', 'NL'),
  ('俄羅斯', 'RU'),
  ('俄罗斯', 'RU'),
  ('莫斯科', 'RU'),
  ('加拿大', 'CA'),
  ('澳大利亞', 'AU'),
  ('澳大利亚', 'AU'),
  ('悉尼', 'AU'),
  ('印尼', 'ID'),
  ('印度尼西亞', 'ID'),
  ('印度尼西亚', 'ID'),
  ('雅加達', 'ID'),
  ('雅加达', 'ID'),
  ('印度', 'IN'),
  ('土耳其', 'TR'),
  ('越南', 'VN'),
  ('泰國', 'TH'),
  ('泰国', 'TH'),
  ('曼谷', 'TH'),
  ('馬來西亞', 'MY'),
  ('马来西亚', 'MY'),
  ('菲律賓', 'PH'),
  ('菲律宾', 'PH'),
  ('巴西', 'BR'),
  ('阿根廷', 'AR'),
  ('阿聯酋', 'AE'),
  ('阿联酋', 'AE'),
  ('迪拜', 'AE'),
  ('以色列', 'IL'),
  ('南非', 'ZA'),
  ('智利', 'CL'),
  ('墨西哥', 'MX'),
  ('西班牙', 'ES'),
  ('意大利', 'IT'),
  ('愛爾蘭', 'IE'),
  ('爱尔兰', 'IE'),
  ('奧地利', 'AT'),
  ('奥地利', 'AT'),
  ('挪威', 'NO'),
  ('丹麥', 'DK'),
  ('丹麦', 'DK'),
  ('瑞士', 'CH'),
  ('瑞典', 'SE'),
  ('芬蘭', 'FI'),
  ('芬兰', 'FI'),
  ('波蘭', 'PL'),
  ('波兰', 'PL'),
  ('烏克蘭', 'UA'),
  ('乌克兰', 'UA'),
  ('中國', 'CN'),
  ('中国', 'CN'),
];

const _spelledRegions = <(String, String)>[
  ('hongkong', 'HK'),
  ('taiwan', 'TW'),
  ('japan', 'JP'),
  ('tokyo', 'JP'),
  ('osaka', 'JP'),
  ('korea', 'KR'),
  ('seoul', 'KR'),
  ('singapore', 'SG'),
  ('losangeles', 'US'),
  ('sanjose', 'US'),
  ('seattle', 'US'),
  ('newyork', 'US'),
  ('dallas', 'US'),
  ('chicago', 'US'),
  ('miami', 'US'),
  ('phoenix', 'US'),
  ('america', 'US'),
  ('london', 'GB'),
  ('britain', 'GB'),
  ('germany', 'DE'),
  ('frankfurt', 'DE'),
  ('france', 'FR'),
  ('paris', 'FR'),
  ('netherlands', 'NL'),
  ('amsterdam', 'NL'),
  ('russia', 'RU'),
  ('moscow', 'RU'),
  ('canada', 'CA'),
  ('toronto', 'CA'),
  ('australia', 'AU'),
  ('sydney', 'AU'),
  ('indonesia', 'ID'),
  ('jakarta', 'ID'),
  ('india', 'IN'),
  ('mumbai', 'IN'),
  ('turkey', 'TR'),
  ('istanbul', 'TR'),
  ('vietnam', 'VN'),
  ('thailand', 'TH'),
  ('bangkok', 'TH'),
  ('malaysia', 'MY'),
  ('philippines', 'PH'),
  ('manila', 'PH'),
  ('brazil', 'BR'),
  ('argentina', 'AR'),
  ('dubai', 'AE'),
  ('israel', 'IL'),
  ('southafrica', 'ZA'),
  ('chile', 'CL'),
  ('mexico', 'MX'),
  ('spain', 'ES'),
  ('madrid', 'ES'),
  ('italy', 'IT'),
  ('milan', 'IT'),
  ('ireland', 'IE'),
  ('dublin', 'IE'),
  ('austria', 'AT'),
  ('vienna', 'AT'),
  ('norway', 'NO'),
  ('sweden', 'SE'),
  ('stockholm', 'SE'),
  ('finland', 'FI'),
  ('helsinki', 'FI'),
  ('denmark', 'DK'),
  ('poland', 'PL'),
  ('warsaw', 'PL'),
  ('ukraine', 'UA'),
  ('switzerland', 'CH'),
  ('zurich', 'CH'),
  ('china', 'CN'),
];

/// Bare region codes, plus the few three-letter forms that show up in node
/// names. Matched as whole tokens only.
const _codeTokens = <String, String>{
  'hk': 'HK',
  'mo': 'MO',
  'tw': 'TW',
  'jp': 'JP',
  'kr': 'KR',
  'sg': 'SG',
  'us': 'US',
  'usa': 'US',
  'uk': 'GB',
  'gb': 'GB',
  'de': 'DE',
  'fr': 'FR',
  'nl': 'NL',
  'ru': 'RU',
  'ca': 'CA',
  'au': 'AU',
  'in': 'IN',
  'tr': 'TR',
  'vn': 'VN',
  'th': 'TH',
  'my': 'MY',
  'ph': 'PH',
  'id': 'ID',
  'br': 'BR',
  'ar': 'AR',
  'ae': 'AE',
  'il': 'IL',
  'za': 'ZA',
  'cl': 'CL',
  'mx': 'MX',
  'es': 'ES',
  'it': 'IT',
  'ie': 'IE',
  'at': 'AT',
  'no': 'NO',
  'se': 'SE',
  'fi': 'FI',
  'dk': 'DK',
  'pl': 'PL',
  'ua': 'UA',
  'ch': 'CH',
  'cn': 'CN',
};
