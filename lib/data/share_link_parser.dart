/// Parsers for the proxy share-link formats commonly produced by panels.
///
/// Every parser returns a [ProxyNode] whose `raw` map is already a valid
/// sing-box outbound body, so [ProxyNode.toOutbound] needs no protocol
/// knowledge of its own.
library;

import 'dart:convert';

import '../models/node.dart';

class ShareLinkParseException implements Exception {
  ShareLinkParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ShareLinkParser {
  const ShareLinkParser._();

  /// Parses a newline/whitespace separated list of links, skipping the ones
  /// that fail so a single bad entry cannot discard a whole subscription.
  static ({List<ProxyNode> nodes, int skipped}) parseMany(
    String input, {
    String? subscriptionId,
  }) {
    final nodes = <ProxyNode>[];
    var skipped = 0;
    for (final line in const LineSplitter().convert(input)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      try {
        nodes.add(parse(trimmed, subscriptionId: subscriptionId));
      } on Object {
        skipped++;
      }
    }
    return (nodes: nodes, skipped: skipped);
  }

  static ProxyNode parse(String link, {String? subscriptionId}) {
    final trimmed = link.trim();
    final schemeEnd = trimmed.indexOf('://');
    if (schemeEnd <= 0) {
      throw ShareLinkParseException('Not a share link: missing scheme');
    }
    final scheme = trimmed.substring(0, schemeEnd).toLowerCase();
    return switch (scheme) {
      'vmess' => _parseVmess(trimmed, subscriptionId),
      'vless' => _parseVless(trimmed, subscriptionId),
      'trojan' => _parseTrojan(trimmed, subscriptionId),
      'ss' => _parseShadowsocks(trimmed, subscriptionId),
      'hysteria2' || 'hy2' => _parseHysteria2(trimmed, subscriptionId),
      'tuic' => _parseTuic(trimmed, subscriptionId),
      'anytls' => _parseAnyTls(trimmed, subscriptionId),
      'socks' ||
      'socks5' =>
        _parseSocksHttp(trimmed, NodeProtocol.socks, subscriptionId),
      'http' ||
      'https' =>
        _parseSocksHttp(trimmed, NodeProtocol.http, subscriptionId),
      _ => throw ShareLinkParseException('Unsupported scheme: $scheme'),
    };
  }

  // ---------------------------------------------------------------- vmess

  /// vmess links are a base64 blob of JSON (v2rayN style).
  static ProxyNode _parseVmess(String link, String? subscriptionId) {
    final payload = link.substring('vmess://'.length);
    final decoded = _decodeBase64(payload);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(decoded) as Map<String, dynamic>;
    } on Object {
      throw ShareLinkParseException('vmess: payload is not JSON');
    }

    final server = (json['add'] ?? '').toString();
    final port = _toInt(json['port']);
    final uuid = (json['id'] ?? '').toString();
    if (server.isEmpty || port == 0 || uuid.isEmpty) {
      throw ShareLinkParseException('vmess: missing add/port/id');
    }

    final network = (json['net'] ?? 'tcp').toString();
    final tlsMode = (json['tls'] ?? '').toString();
    final host = (json['host'] ?? '').toString();
    final path = (json['path'] ?? '').toString();
    final sni = (json['sni'] ?? '').toString();

    final raw = <String, dynamic>{
      'uuid': uuid,
      'security': (json['scy'] ?? 'auto').toString(),
      if (_toInt(json['aid']) > 0) 'alter_id': _toInt(json['aid']),
    };

    if (tlsMode == 'tls' || tlsMode == 'reality') {
      raw['tls'] = {
        'enabled': true,
        'server_name': sni.isNotEmpty ? sni : (host.isNotEmpty ? host : server),
        if ((json['alpn'] ?? '').toString().isNotEmpty)
          'alpn': json['alpn'].toString().split(','),
        if ((json['fp'] ?? '').toString().isNotEmpty)
          'utls': {'enabled': true, 'fingerprint': json['fp'].toString()},
      };
    }

    final transport = _buildTransport(
      network: network,
      host: host,
      path: path,
      serviceName: (json['path'] ?? '').toString(),
    );
    if (transport != null) raw['transport'] = transport;

    final name = (json['ps'] ?? '').toString();
    return ProxyNode(
      id: _makeId('vmess', server, port, uuid),
      name: name.isNotEmpty ? name : '$server:$port',
      protocol: NodeProtocol.vmess,
      server: server,
      serverPort: port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // ---------------------------------------------------------------- vless

  static ProxyNode _parseVless(String link, String? subscriptionId) {
    final uri = _parseUri(link, 'vless');
    final uuid = Uri.decodeComponent(uri.userInfo);
    if (uuid.isEmpty) throw ShareLinkParseException('vless: missing uuid');

    final query = uri.queryParameters;
    final raw = <String, dynamic>{'uuid': uuid};

    final flow = query['flow'] ?? '';
    if (flow.isNotEmpty) raw['flow'] = flow;

    final security = query['security'] ?? 'none';
    if (security == 'tls' || security == 'reality') {
      final tls = <String, dynamic>{
        'enabled': true,
        'server_name': query['sni'] ?? query['host'] ?? uri.host,
      };
      if ((query['alpn'] ?? '').isNotEmpty) {
        tls['alpn'] = query['alpn']!.split(',');
      }
      if ((query['fp'] ?? '').isNotEmpty) {
        tls['utls'] = {'enabled': true, 'fingerprint': query['fp']};
      }
      if (security == 'reality') {
        tls['reality'] = {
          'enabled': true,
          if ((query['pbk'] ?? '').isNotEmpty) 'public_key': query['pbk'],
          if ((query['sid'] ?? '').isNotEmpty) 'short_id': query['sid'],
        };
      }
      if (query['allowInsecure'] == '1' || query['insecure'] == '1') {
        tls['insecure'] = true;
      }
      raw['tls'] = tls;
    }

    final transport = _buildTransport(
      network: query['type'] ?? 'tcp',
      host: query['host'] ?? '',
      path: query['path'] ?? '',
      serviceName: query['serviceName'] ?? '',
    );
    if (transport != null) raw['transport'] = transport;

    return ProxyNode(
      id: _makeId('vless', uri.host, uri.port, uuid),
      name: _fragmentName(uri, '${uri.host}:${uri.port}'),
      protocol: NodeProtocol.vless,
      server: uri.host,
      serverPort: uri.port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // --------------------------------------------------------------- trojan

  static ProxyNode _parseTrojan(String link, String? subscriptionId) {
    final uri = _parseUri(link, 'trojan');
    final password = Uri.decodeComponent(uri.userInfo);
    if (password.isEmpty) {
      throw ShareLinkParseException('trojan: missing password');
    }

    final query = uri.queryParameters;
    final raw = <String, dynamic>{
      'password': password,
      'tls': {
        'enabled': true,
        'server_name': query['sni'] ?? query['peer'] ?? uri.host,
        if ((query['alpn'] ?? '').isNotEmpty) 'alpn': query['alpn']!.split(','),
        if ((query['fp'] ?? '').isNotEmpty)
          'utls': {'enabled': true, 'fingerprint': query['fp']},
        if (query['allowInsecure'] == '1' || query['insecure'] == '1')
          'insecure': true,
      },
    };

    final transport = _buildTransport(
      network: query['type'] ?? 'tcp',
      host: query['host'] ?? '',
      path: query['path'] ?? '',
      serviceName: query['serviceName'] ?? '',
    );
    if (transport != null) raw['transport'] = transport;

    return ProxyNode(
      id: _makeId('trojan', uri.host, uri.port, password),
      name: _fragmentName(uri, '${uri.host}:${uri.port}'),
      protocol: NodeProtocol.trojan,
      server: uri.host,
      serverPort: uri.port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // ---------------------------------------------------------- shadowsocks

  /// Handles both `ss://base64(method:pass)@host:port` (SIP002) and the older
  /// fully base64-encoded form.
  static ProxyNode _parseShadowsocks(String link, String? subscriptionId) {
    var body = link.substring('ss://'.length);

    String? fragment;
    final hashIndex = body.indexOf('#');
    if (hashIndex >= 0) {
      fragment = Uri.decodeComponent(body.substring(hashIndex + 1));
      body = body.substring(0, hashIndex);
    }

    // Strip plugin/query params; sing-box handles plugins separately and we
    // do not claim support for them here.
    final queryIndex = body.indexOf('?');
    Map<String, String> query = const {};
    if (queryIndex >= 0) {
      query = Uri.splitQueryString(body.substring(queryIndex + 1));
      body = body.substring(0, queryIndex);
    }

    String method;
    String password;
    String server;
    int port;

    final atIndex = body.lastIndexOf('@');
    if (atIndex > 0) {
      // SIP002: userinfo may be base64 or plain `method:password`.
      final userInfo = body.substring(0, atIndex);
      final hostPart = body.substring(atIndex + 1);
      final credentials =
          userInfo.contains(':') ? userInfo : _decodeBase64(userInfo);
      final colon = credentials.indexOf(':');
      if (colon <= 0) {
        throw ShareLinkParseException('ss: malformed credentials');
      }
      method = credentials.substring(0, colon);
      password = credentials.substring(colon + 1);
      final hostPort = _splitHostPort(hostPart);
      server = hostPort.host;
      port = hostPort.port;
    } else {
      // Legacy: whole body is base64 of `method:password@host:port`.
      final decoded = _decodeBase64(body);
      final at = decoded.lastIndexOf('@');
      if (at <= 0) throw ShareLinkParseException('ss: malformed legacy link');
      final credentials = decoded.substring(0, at);
      final colon = credentials.indexOf(':');
      if (colon <= 0) {
        throw ShareLinkParseException('ss: malformed legacy credentials');
      }
      method = credentials.substring(0, colon);
      password = credentials.substring(colon + 1);
      final hostPort = _splitHostPort(decoded.substring(at + 1));
      server = hostPort.host;
      port = hostPort.port;
    }

    if (server.isEmpty || port == 0) {
      throw ShareLinkParseException('ss: missing host/port');
    }

    final raw = <String, dynamic>{
      'method': method,
      'password': password,
      if ((query['plugin'] ?? '').isNotEmpty)
        ...(() {
          // `plugin=obfs-local;obfs=http;obfs-host=x` -> plugin + plugin_opts
          final plugin = query['plugin']!;
          final semi = plugin.indexOf(';');
          return {
            'plugin': semi > 0 ? plugin.substring(0, semi) : plugin,
            if (semi > 0) 'plugin_opts': plugin.substring(semi + 1),
          };
        })(),
    };

    return ProxyNode(
      id: _makeId('ss', server, port, password),
      name: fragment?.isNotEmpty == true ? fragment! : '$server:$port',
      protocol: NodeProtocol.shadowsocks,
      server: server,
      serverPort: port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // ------------------------------------------------------------ hysteria2

  static ProxyNode _parseHysteria2(String link, String? subscriptionId) {
    final scheme = link.startsWith('hy2://') ? 'hy2' : 'hysteria2';
    final uri = _parseUri(link, scheme);
    final query = uri.queryParameters;

    final raw = <String, dynamic>{
      'password': Uri.decodeComponent(uri.userInfo),
      'tls': {
        'enabled': true,
        'server_name': query['sni'] ?? uri.host,
        if ((query['alpn'] ?? '').isNotEmpty) 'alpn': query['alpn']!.split(','),
        if (query['insecure'] == '1' || query['allowInsecure'] == '1')
          'insecure': true,
      },
      if ((query['obfs'] ?? '').isNotEmpty)
        'obfs': {
          'type': query['obfs'],
          if ((query['obfs-password'] ?? '').isNotEmpty)
            'password': query['obfs-password'],
        },
    };

    return ProxyNode(
      id: _makeId('hysteria2', uri.host, uri.port, uri.userInfo),
      name: _fragmentName(uri, '${uri.host}:${uri.port}'),
      protocol: NodeProtocol.hysteria2,
      server: uri.host,
      serverPort: uri.port == 0 ? 443 : uri.port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // ----------------------------------------------------------------- tuic

  static ProxyNode _parseTuic(String link, String? subscriptionId) {
    final uri = _parseUri(link, 'tuic');
    final query = uri.queryParameters;

    final userInfo = Uri.decodeComponent(uri.userInfo);
    final colon = userInfo.indexOf(':');
    if (colon <= 0) {
      throw ShareLinkParseException('tuic: expected uuid:password');
    }

    final raw = <String, dynamic>{
      'uuid': userInfo.substring(0, colon),
      'password': userInfo.substring(colon + 1),
      if ((query['congestion_control'] ?? '').isNotEmpty)
        'congestion_control': query['congestion_control'],
      if ((query['udp_relay_mode'] ?? '').isNotEmpty)
        'udp_relay_mode': query['udp_relay_mode'],
      'tls': {
        'enabled': true,
        'server_name': query['sni'] ?? uri.host,
        if ((query['alpn'] ?? '').isNotEmpty) 'alpn': query['alpn']!.split(','),
        if (query['allow_insecure'] == '1' || query['insecure'] == '1')
          'insecure': true,
      },
    };

    return ProxyNode(
      id: _makeId('tuic', uri.host, uri.port, userInfo),
      name: _fragmentName(uri, '${uri.host}:${uri.port}'),
      protocol: NodeProtocol.tuic,
      server: uri.host,
      serverPort: uri.port == 0 ? 443 : uri.port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // --------------------------------------------------------------- anytls

  static ProxyNode _parseAnyTls(String link, String? subscriptionId) {
    final uri = _parseUri(link, 'anytls');
    final query = uri.queryParameters;
    final raw = <String, dynamic>{
      'password': Uri.decodeComponent(uri.userInfo),
      'tls': {
        'enabled': true,
        'server_name': query['sni'] ?? uri.host,
        if (query['insecure'] == '1' || query['allowInsecure'] == '1')
          'insecure': true,
      },
    };
    return ProxyNode(
      id: _makeId('anytls', uri.host, uri.port, uri.userInfo),
      name: _fragmentName(uri, '${uri.host}:${uri.port}'),
      protocol: NodeProtocol.anytls,
      server: uri.host,
      serverPort: uri.port == 0 ? 443 : uri.port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // ---------------------------------------------------------- socks / http

  static ProxyNode _parseSocksHttp(
    String link,
    NodeProtocol protocol,
    String? subscriptionId,
  ) {
    final scheme = link.substring(0, link.indexOf('://'));
    final uri = _parseUri(link, scheme);
    final raw = <String, dynamic>{};

    final userInfo = Uri.decodeComponent(uri.userInfo);
    if (userInfo.isNotEmpty) {
      final colon = userInfo.indexOf(':');
      if (colon > 0) {
        raw['username'] = userInfo.substring(0, colon);
        raw['password'] = userInfo.substring(colon + 1);
      }
    }
    if (protocol == NodeProtocol.socks) raw['version'] = '5';
    if (scheme == 'https') {
      raw['tls'] = {'enabled': true, 'server_name': uri.host};
    }

    return ProxyNode(
      id: _makeId(scheme, uri.host, uri.port, userInfo),
      name: _fragmentName(uri, '${uri.host}:${uri.port}'),
      protocol: protocol,
      server: uri.host,
      serverPort: uri.port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // -------------------------------------------------------------- helpers

  /// Builds a sing-box `transport` object, or null for plain TCP.
  static Map<String, dynamic>? _buildTransport({
    required String network,
    required String host,
    required String path,
    required String serviceName,
  }) {
    switch (network) {
      case 'ws':
        return {
          'type': 'ws',
          if (path.isNotEmpty) 'path': path,
          if (host.isNotEmpty) 'headers': {'Host': host},
        };
      case 'grpc':
        return {
          'type': 'grpc',
          if (serviceName.isNotEmpty) 'service_name': serviceName,
        };
      case 'h2' || 'http':
        return {
          'type': 'http',
          if (host.isNotEmpty) 'host': [host],
          if (path.isNotEmpty) 'path': path,
        };
      case 'httpupgrade':
        return {
          'type': 'httpupgrade',
          if (host.isNotEmpty) 'host': host,
          if (path.isNotEmpty) 'path': path,
        };
      case 'quic':
        return {'type': 'quic'};
      default:
        return null;
    }
  }

  /// Share links routinely omit base64 padding and use the URL-safe alphabet.
  static String _decodeBase64(String input) {
    var value = input.replaceAll('-', '+').replaceAll('_', '/').trim();
    final remainder = value.length % 4;
    if (remainder > 0) {
      value = value.padRight(value.length + 4 - remainder, '=');
    }
    try {
      return utf8.decode(base64.decode(value));
    } on Object {
      throw ShareLinkParseException('Invalid base64 payload');
    }
  }

  /// `Uri.parse` rejects some real-world links (unencoded fragments, empty
  /// paths), so normalise before parsing and surface a clear error.
  static Uri _parseUri(String link, String expectedScheme) {
    try {
      final uri = Uri.parse(link);
      if (uri.host.isEmpty) {
        throw ShareLinkParseException('$expectedScheme: missing host');
      }
      return uri;
    } on ShareLinkParseException {
      rethrow;
    } on Object {
      throw ShareLinkParseException('$expectedScheme: malformed URI');
    }
  }

  static ({String host, int port}) _splitHostPort(String value) {
    // IPv6 literals arrive as [::1]:443
    if (value.startsWith('[')) {
      final close = value.indexOf(']');
      if (close > 0) {
        final host = value.substring(1, close);
        final rest = value.substring(close + 1);
        final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : 0;
        return (host: host, port: port ?? 0);
      }
    }
    final colon = value.lastIndexOf(':');
    if (colon <= 0) return (host: value, port: 0);
    return (
      host: value.substring(0, colon),
      port: int.tryParse(value.substring(colon + 1)) ?? 0,
    );
  }

  static String _fragmentName(Uri uri, String fallback) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) return fallback;
    try {
      return Uri.decodeComponent(fragment);
    } on Object {
      return fragment;
    }
  }

  static int _toInt(Object? value) => switch (value) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v) ?? 0,
        _ => 0,
      };

  /// Stable id so re-importing the same subscription keeps latency/favorites.
  static String _makeId(String scheme, String host, int port, String secret) {
    final material = '$scheme|$host|$port|$secret';
    var hash = 0x811c9dc5;
    for (final unit in material.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
