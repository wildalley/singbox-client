/// Asks the network what address it sees us coming from.
///
/// This is the one check that answers "is the tunnel actually carrying my
/// traffic", which no local counter can: bytes moving and a node selected both
/// look identical whether the exit is the node or the user's own line. Only an
/// outside observer reporting back a foreign address settles it.
///
/// The request goes out through the loopback inbound whenever the tunnel is up —
/// see `local_proxy.dart`. Sent directly it would report the user's real address
/// on Android, where the app is excluded from the VPN, and on desktop in
/// system-proxy mode, where Dart's HttpClient ignores the desktop's proxy
/// setting. Through the inbound it reports the exit for every platform and mode,
/// because the config renders that inbound unconditionally.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_proxy.dart';

/// The address the outside world sees, and where it places it.
class ExitAddress {
  const ExitAddress({required this.ip, this.countryCode, this.countryName});

  final String ip;

  /// Two-letter code, upper case, or null when the service did not say.
  final String? countryCode;

  /// The country's name as the service gave it — already in its own words, so
  /// it is shown rather than translated.
  final String? countryName;

  @override
  bool operator ==(Object other) =>
      other is ExitAddress &&
      other.ip == ip &&
      other.countryCode == countryCode &&
      other.countryName == countryName;

  @override
  int get hashCode => Object.hash(ip, countryCode, countryName);

  @override
  String toString() => 'ExitAddress($ip, $countryCode)';
}

/// One service that will report our address back to us.
///
/// Two of them, because a single free endpoint rate-limits: ipinfo.io already
/// answers 429 from an ordinary desktop, and a lookup that fails looks to the
/// user like a tunnel that failed. The field names differ per service, so each
/// carries its own.
class IpEchoService {
  const IpEchoService(this.url, {required this.codeKey});

  final String url;

  /// Key holding the two-letter country code.
  final String codeKey;

  static const defaults = <IpEchoService>[
    IpEchoService('https://api.ip.sb/geoip', codeKey: 'country_code'),
    IpEchoService('https://ifconfig.co/json', codeKey: 'country_iso'),
  ];
}

/// Reads the exit address, or null when nothing would answer.
class IpLookup {
  IpLookup({
    HttpClient? httpClient,
    this.services = IpEchoService.defaults,
    this.timeout = const Duration(seconds: 8),
  }) : _httpClient = httpClient ?? (HttpClient()..connectionTimeout = timeout);

  final HttpClient _httpClient;
  final List<IpEchoService> services;

  /// Short on purpose. This is a nicety on a dashboard, not a step in
  /// connecting, so it gives up well before a user wonders if it hung.
  final Duration timeout;

  /// The address, or null if every service failed.
  ///
  /// Never throws: an unreachable echo service says nothing about the tunnel
  /// that the caller could act on, and the UI shows "unknown" either way.
  Future<ExitAddress?> fetch({required bool viaLocalProxy}) async {
    routeHttp(_httpClient, viaLocalProxy: viaLocalProxy);
    for (final service in services) {
      try {
        final address = await _fetchOne(service);
        if (address != null) return address;
      } on Object {
        // Rate-limited, blocked, or offline. Try the next one.
      }
    }
    return null;
  }

  Future<ExitAddress?> _fetchOne(IpEchoService service) async {
    final request = await _httpClient
        .getUrl(Uri.parse(service.url))
        .timeout(timeout);
    // Some echo services hand a browser an HTML page unless asked otherwise.
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    final body =
        await response.transform(utf8.decoder).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) return null;
    return parseEcho(body);
  }

  void dispose() => _httpClient.close(force: true);

  /// Reads [body] as one of the echo services' replies.
  ///
  /// Tolerant by design: every one of these is a third party free to add and
  /// rename fields, and an address with no country is still worth showing. Only
  /// `ip` is required, and it is checked rather than trusted — a rate-limit body
  /// is also valid JSON, and pasting its error text into the dashboard as an
  /// address would read as a working lookup.
  static ExitAddress? parseEcho(String body, {String? codeKey}) {
    Object? raw;
    try {
      raw = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (raw is! Map<String, Object?>) return null;
    final decoded = raw;

    final ip = decoded['ip'];
    if (ip is! String || !_looksLikeAddress(ip)) return null;

    String? text(String key) {
      final value = decoded[key];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    // Whichever of the two field names is present, so one parser serves both
    // services and a caller need not know which answered.
    final code = codeKey != null
        ? text(codeKey)
        : text('country_code') ?? text('country_iso');

    return ExitAddress(
      ip: ip,
      countryCode: code?.toUpperCase(),
      countryName: text('country'),
    );
  }

  /// Whether [value] parses as an IPv4 or IPv6 literal.
  static bool _looksLikeAddress(String value) {
    try {
      InternetAddress(value);
      return true;
    } on ArgumentError {
      return false;
    }
  }
}
