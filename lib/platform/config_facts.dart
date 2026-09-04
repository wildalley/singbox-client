/// Typed facts extracted from a rendered sing-box configuration.
///
/// Desktop controllers receive one JSON string so the platform boundary stays
/// small. They still need the same few runtime facts after decoding it: where
/// the Clash API listens, how it is authenticated, which local proxy port is
/// available, and whether a TUN inbound requires privileged startup. Keeping
/// that decoding here prevents the Linux and Windows paths from silently
/// acquiring different defaults.
library;

import 'dart:convert';

import '../data/config_builder.dart';

class ConfigFacts {
  const ConfigFacts({
    required this.clashPort,
    required this.clashSecret,
    required this.mixedPort,
    required this.hasTun,
  });

  final int clashPort;
  final String clashSecret;
  final int mixedPort;
  final bool hasTun;

  /// Desktop system-proxy mode is represented by the absence of a TUN inbound
  /// in the generated config. A TUN config can still carry its own platform
  /// proxy block; the host-specific controller decides whether to apply that
  /// optional block.
  bool get wantsSystemProxy => !hasTun;

  /// Parses and validates the minimum control-plane shape required by the
  /// desktop runtimes. A malformed config is rejected before a process starts,
  /// instead of becoming an API timeout several seconds later.
  static ConfigFacts parse(String configJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(configJson);
    } on FormatException catch (error) {
      throw FormatException('config is not valid JSON: ${error.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('config must be an object');
    }
    return fromMap(Map<Object?, Object?>.from(decoded));
  }

  /// Same parser for a decoded config, useful when a platform adapts inbound
  /// entries before launching the core.
  static ConfigFacts fromMap(Map<Object?, Object?> root) {
    final experimental = _map(root['experimental']);
    final clash = _map(experimental?['clash_api']);
    if (clash == null) {
      throw const FormatException('config has no Clash API');
    }

    final secret = clash['secret']?.toString().trim() ?? '';
    if (secret.isEmpty) {
      throw const FormatException('config has no Clash API secret');
    }

    final controller = clash['external_controller']?.toString().trim() ?? '';
    final clashPort = _portFromController(controller);

    final inbounds = root['inbounds'];
    if (inbounds is! List) {
      throw const FormatException('config has no inbounds');
    }

    var mixedPort = ConfigBuilder.localProxyPort;
    var hasTun = false;
    for (final raw in inbounds) {
      final inbound = _map(raw);
      if (inbound == null) continue;
      final type = inbound['type']?.toString().toLowerCase();
      if (type == 'tun') hasTun = true;
      if (type != 'mixed') continue;

      final rawPort = inbound['listen_port'];
      if (rawPort == null) continue;
      final port = _validPort(rawPort, field: 'inbound listen_port');
      // Match the existing runtime behaviour for configs with more than one
      // local inbound: the last explicitly configured endpoint wins.
      mixedPort = port;
    }

    return ConfigFacts(
      clashPort: clashPort,
      clashSecret: secret,
      mixedPort: mixedPort,
      hasTun: hasTun,
    );
  }

  static Map<Object?, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    return Map<Object?, Object?>.from(value);
  }

  static int _portFromController(String value) {
    if (value.isEmpty) {
      throw const FormatException('config has no Clash API endpoint');
    }

    // Uri handles both host:port and [ipv6]:port once a scheme is supplied.
    // A controller URL is not required to carry one in sing-box configs.
    final uri = Uri.tryParse(
      value.contains('://') ? value : 'http://$value',
    );
    final port = uri?.port;
    if (uri == null || !uri.hasPort || port == null || port == 0) {
      throw const FormatException('config has an invalid Clash API port');
    }
    return _validPort(port, field: 'Clash API port');
  }

  static int _validPort(Object value, {required String field}) {
    final int? port;
    if (value is int) {
      port = value;
    } else if (value is num && value == value.truncateToDouble()) {
      port = value.toInt();
    } else if (value is String) {
      port = int.tryParse(value);
    } else {
      port = null;
    }
    if (port == null || port < 1 || port > 65535) {
      throw FormatException('$field is invalid');
    }
    return port;
  }
}
