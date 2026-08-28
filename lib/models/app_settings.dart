/// Persisted user settings that affect the rendered sing-box config.
library;

enum RoutingMode {
  /// Everything through the proxy.
  global('Global'),

  /// Rule-based: CN direct, ads blocked, rest proxied.
  rule('Rule'),

  /// Everything direct (proxy stays off the path).
  direct('Direct');

  const RoutingMode(this.label);

  final String label;

  static RoutingMode fromName(String? value) => RoutingMode.values.firstWhere(
        (item) => item.name == value,
        orElse: () => RoutingMode.rule,
      );
}

enum LogLevel {
  trace,
  debug,
  info,
  warn,
  error;

  static LogLevel fromName(String? value) => LogLevel.values.firstWhere(
        (item) => item.name == value,
        orElse: () => LogLevel.info,
      );
}

/// Appearance preference. [system] follows the platform setting.
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromName(String? value) =>
      AppThemeMode.values.firstWhere(
        (item) => item.name == value,
        orElse: () => AppThemeMode.system,
      );
}

/// UI language. [system] follows the platform locale, falling back to English
/// for anything the app does not translate.
enum AppLanguage {
  system(null),
  english('en'),
  chinese('zh');

  const AppLanguage(this.code);

  /// BCP-47 language subtag, or null for [system].
  final String? code;

  static AppLanguage fromCode(String? value) => AppLanguage.values.firstWhere(
        (item) => item.code == value,
        orElse: () => AppLanguage.system,
      );
}

/// sing-box TUN network stack.
enum TunStack {
  system('system', 'System'),
  gvisor('gvisor', 'gVisor'),
  mixed('mixed', 'Mixed');

  const TunStack(this.tag, this.label);

  final String tag;
  final String label;

  static TunStack fromTag(String? value) => TunStack.values.firstWhere(
        (item) => item.tag == value,
        orElse: () => TunStack.mixed,
      );
}

class AppSettings {
  const AppSettings({
    this.routingMode = RoutingMode.rule,
    this.mtu = 9000,
    this.ipv6 = false,
    this.strictRoute = false,
    this.dnsRemote = 'https://1.1.1.1/dns-query',
    this.dnsDirect = 'https://223.5.5.5/dns-query',
    this.blockAds = true,
    this.bypassLan = true,
    this.fakeIp = false,
    this.tunStack = TunStack.mixed,
    this.systemProxy = false,
    this.logLevel = LogLevel.info,
    this.themeMode = AppThemeMode.system,
    this.language = AppLanguage.system,
    this.perAppProxyEnabled = false,
    this.perAppProxyBypass = const [],
  });

  final RoutingMode routingMode;
  final int mtu;
  final bool ipv6;
  final bool strictRoute;

  /// Remote resolver used for proxied domains. Accepts a `https://` or
  /// `tls://` URL; see [remoteDnsType] and [remoteDnsHost].
  final String dnsRemote;
  final String dnsDirect;
  final bool blockAds;
  final bool bypassLan;

  /// FakeIP speeds up connections but breaks apps that need real addresses.
  final bool fakeIp;
  final TunStack tunStack;

  /// Exposes an HTTP proxy on the TUN inbound for apps that ignore the VPN.
  final bool systemProxy;
  final LogLevel logLevel;

  /// Presentation only; neither affects the rendered sing-box config.
  final AppThemeMode themeMode;
  final AppLanguage language;

  /// When enabled, [perAppProxyBypass] packages are excluded from the tunnel.
  final bool perAppProxyEnabled;
  final List<String> perAppProxyBypass;

  /// sing-box DNS server `type` derived from [dnsRemote]'s scheme.
  String get remoteDnsType => switch (Uri.tryParse(dnsRemote)?.scheme) {
        'tls' => 'tls',
        'quic' => 'quic',
        'h3' => 'h3',
        'udp' => 'udp',
        'tcp' => 'tcp',
        _ => 'https',
      };

  /// Bare host for [dnsRemote], with the scheme and any path removed.
  String get remoteDnsHost {
    final uri = Uri.tryParse(dnsRemote);
    if (uri == null || uri.host.isEmpty) {
      return dnsRemote.replaceAll(RegExp(r'^\w+://'), '').split('/').first;
    }
    return uri.host;
  }

  /// Path component for DoH servers (`/dns-query`), empty for other types.
  String get remoteDnsPath {
    if (remoteDnsType != 'https' && remoteDnsType != 'h3') return '';
    final path = Uri.tryParse(dnsRemote)?.path ?? '';
    return path == '/' ? '' : path;
  }

  String get directDnsType => switch (Uri.tryParse(dnsDirect)?.scheme) {
        'tls' => 'tls',
        'quic' => 'quic',
        'h3' => 'h3',
        'udp' => 'udp',
        'tcp' => 'tcp',
        _ => 'https',
      };

  String get directDnsHost {
    final uri = Uri.tryParse(dnsDirect);
    if (uri == null || uri.host.isEmpty) {
      return dnsDirect.replaceAll(RegExp(r'^\w+://'), '').split('/').first;
    }
    return uri.host;
  }

  String get directDnsPath {
    if (directDnsType != 'https' && directDnsType != 'h3') return '';
    final path = Uri.tryParse(dnsDirect)?.path ?? '';
    return path == '/' ? '' : path;
  }

  AppSettings copyWith({
    RoutingMode? routingMode,
    int? mtu,
    bool? ipv6,
    bool? strictRoute,
    String? dnsRemote,
    String? dnsDirect,
    bool? blockAds,
    bool? bypassLan,
    bool? fakeIp,
    TunStack? tunStack,
    bool? systemProxy,
    LogLevel? logLevel,
    AppThemeMode? themeMode,
    AppLanguage? language,
    bool? perAppProxyEnabled,
    List<String>? perAppProxyBypass,
  }) {
    return AppSettings(
      routingMode: routingMode ?? this.routingMode,
      mtu: mtu ?? this.mtu,
      ipv6: ipv6 ?? this.ipv6,
      strictRoute: strictRoute ?? this.strictRoute,
      dnsRemote: dnsRemote ?? this.dnsRemote,
      dnsDirect: dnsDirect ?? this.dnsDirect,
      blockAds: blockAds ?? this.blockAds,
      bypassLan: bypassLan ?? this.bypassLan,
      fakeIp: fakeIp ?? this.fakeIp,
      tunStack: tunStack ?? this.tunStack,
      systemProxy: systemProxy ?? this.systemProxy,
      logLevel: logLevel ?? this.logLevel,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      perAppProxyEnabled: perAppProxyEnabled ?? this.perAppProxyEnabled,
      perAppProxyBypass: perAppProxyBypass ?? this.perAppProxyBypass,
    );
  }

  Map<String, dynamic> toJson() => {
        'routing_mode': routingMode.name,
        'mtu': mtu,
        'ipv6': ipv6,
        'strict_route': strictRoute,
        'dns_remote': dnsRemote,
        'dns_direct': dnsDirect,
        'block_ads': blockAds,
        'bypass_lan': bypassLan,
        'fake_ip': fakeIp,
        'tun_stack': tunStack.tag,
        'system_proxy': systemProxy,
        'log_level': logLevel.name,
        'theme_mode': themeMode.name,
        if (language.code != null) 'language': language.code,
        'per_app_proxy_enabled': perAppProxyEnabled,
        'per_app_proxy_bypass': perAppProxyBypass,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        routingMode: RoutingMode.fromName(json['routing_mode'] as String?),
        mtu: (json['mtu'] as num?)?.toInt() ?? 9000,
        ipv6: json['ipv6'] as bool? ?? false,
        strictRoute: json['strict_route'] as bool? ?? false,
        dnsRemote:
            json['dns_remote'] as String? ?? 'https://1.1.1.1/dns-query',
        dnsDirect:
            json['dns_direct'] as String? ?? 'https://223.5.5.5/dns-query',
        blockAds: json['block_ads'] as bool? ?? true,
        bypassLan: json['bypass_lan'] as bool? ?? true,
        fakeIp: json['fake_ip'] as bool? ?? false,
        tunStack: TunStack.fromTag(json['tun_stack'] as String?),
        systemProxy: json['system_proxy'] as bool? ?? false,
        logLevel: LogLevel.fromName(json['log_level'] as String?),
        themeMode: AppThemeMode.fromName(json['theme_mode'] as String?),
        language: AppLanguage.fromCode(json['language'] as String?),
        perAppProxyEnabled: json['per_app_proxy_enabled'] as bool? ?? false,
        perAppProxyBypass: switch (json['per_app_proxy_bypass']) {
          List list => list.map((item) => item.toString()).toList(),
          _ => const <String>[],
        },
      );
}
