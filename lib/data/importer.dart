/// Import pipelines: subscription URL, share links, and sing-box JSON.
library;

import 'dart:convert';
import 'dart:io';

import '../models/node.dart';
import '../models/subscription.dart';
import 'share_link_parser.dart';

class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Outcome of any import: the nodes found plus how many entries were skipped.
class ImportResult {
  const ImportResult({
    required this.nodes,
    this.skipped = 0,
    this.subscriptionName,
    this.expiresAt,
    this.usedBytes,
    this.totalBytes,
  });

  final List<ProxyNode> nodes;
  final int skipped;

  /// Name advertised by the panel (`profile-title` header), if any.
  final String? subscriptionName;
  final DateTime? expiresAt;
  final int? usedBytes;
  final int? totalBytes;
}

class Importer {
  Importer({HttpClient? httpClient})
      : _httpClient = httpClient ?? (HttpClient()..connectionTimeout = _timeout);

  final HttpClient _httpClient;

  static const _timeout = Duration(seconds: 20);
  static const _userAgent = 'sing-box; SingBoxClient/0.1.0';

  /// Detects the format of pasted [text] and imports it.
  ///
  /// Handles a subscription URL, one or more share links, a sing-box JSON
  /// config, and base64-wrapped link lists.
  Future<ImportResult> importText(String text, {String? subscriptionId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ImportException('Nothing to import');

    if (_looksLikeJson(trimmed)) {
      return importSingBoxConfig(trimmed, subscriptionId: subscriptionId);
    }

    // A bare http(s) URL is a subscription, not an http:// proxy share link:
    // share links carry credentials or a fragment, subscriptions do not.
    if (_looksLikeSubscriptionUrl(trimmed)) {
      return fetchSubscription(trimmed, subscriptionId: subscriptionId);
    }

    return importShareLinks(trimmed, subscriptionId: subscriptionId);
  }

  /// Parses one or many share links, transparently unwrapping a base64 blob.
  ImportResult importShareLinks(String text, {String? subscriptionId}) {
    final payload = _maybeDecodeBase64List(text.trim());
    final parsed =
        ShareLinkParser.parseMany(payload, subscriptionId: subscriptionId);
    if (parsed.nodes.isEmpty) {
      throw ImportException(
        parsed.skipped > 0
            ? 'No supported links found (${parsed.skipped} unrecognised)'
            : 'No supported links found',
      );
    }
    return ImportResult(nodes: parsed.nodes, skipped: parsed.skipped);
  }

  /// Extracts usable outbounds from a full or partial sing-box config.
  ///
  /// Accepts a whole config object, a bare `outbounds` array, or a single
  /// outbound object.
  ImportResult importSingBoxConfig(String text, {String? subscriptionId}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on Object {
      throw ImportException('Invalid JSON');
    }

    final List<dynamic> outbounds;
    switch (decoded) {
      case Map map when map['outbounds'] is List:
        outbounds = map['outbounds'] as List;
      case Map map when map['type'] != null:
        outbounds = [map];
      case List list:
        outbounds = list;
      default:
        throw ImportException('No outbounds found in config');
    }

    final nodes = <ProxyNode>[];
    var skipped = 0;
    for (final entry in outbounds) {
      if (entry is! Map) {
        skipped++;
        continue;
      }
      final node = _nodeFromOutbound(
        Map<String, dynamic>.from(entry),
        subscriptionId: subscriptionId,
      );
      if (node == null) {
        skipped++;
      } else {
        nodes.add(node);
      }
    }

    if (nodes.isEmpty) {
      throw ImportException('No usable proxy outbounds in config');
    }
    return ImportResult(nodes: nodes, skipped: skipped);
  }

  /// Reads a config or link-list file from disk.
  Future<ImportResult> importFile(String path, {String? subscriptionId}) async {
    final file = File(path);
    if (!await file.exists()) {
      throw ImportException('File not found: $path');
    }
    final content = await file.readAsString();
    return importText(content, subscriptionId: subscriptionId);
  }

  /// Fetches a subscription URL and parses its body.
  ///
  /// Panels return either a base64 link list or a sing-box JSON config, and
  /// advertise quota/expiry through `subscription-userinfo`.
  Future<ImportResult> fetchSubscription(
    String url, {
    String? subscriptionId,
  }) async {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on Object {
      throw ImportException('Invalid subscription URL');
    }
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw ImportException('Subscription URL must be http or https');
    }

    late HttpClientResponse response;
    String body;
    try {
      final request = await _httpClient.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      response = await request.close().timeout(_timeout);
      body = await response.transform(utf8.decoder).join().timeout(_timeout);
    } on Object catch (error) {
      // Never surface the URL itself: it usually carries the token.
      throw ImportException('Subscription fetch failed: ${_redact(error)}');
    }

    if (response.statusCode != HttpStatus.ok) {
      throw ImportException('Subscription returned HTTP ${response.statusCode}');
    }

    final base = _looksLikeJson(body.trim())
        ? importSingBoxConfig(body, subscriptionId: subscriptionId)
        : importShareLinks(body, subscriptionId: subscriptionId);

    final info = _parseUserInfo(response.headers.value('subscription-userinfo'));
    final title = _decodeHeaderTitle(response.headers.value('profile-title'));

    return ImportResult(
      nodes: base.nodes,
      skipped: base.skipped,
      subscriptionName: title,
      expiresAt: info.expiresAt,
      usedBytes: info.usedBytes,
      totalBytes: info.totalBytes,
    );
  }

  /// Re-fetches [subscription] and returns the refreshed nodes and metadata.
  Future<({Subscription subscription, List<ProxyNode> nodes})> refresh(
    Subscription subscription,
  ) async {
    final url = subscription.url;
    if (url == null || url.isEmpty) {
      throw ImportException('This subscription has no URL to refresh');
    }
    final result =
        await fetchSubscription(url, subscriptionId: subscription.id);
    return (
      subscription: subscription.copyWith(
        name: result.subscriptionName?.isNotEmpty == true
            ? result.subscriptionName
            : null,
        updatedAt: DateTime.now(),
        nodeCount: result.nodes.length,
        expiresAt: result.expiresAt,
        usedBytes: result.usedBytes,
        totalBytes: result.totalBytes,
        clearError: true,
      ),
      nodes: result.nodes,
    );
  }

  void dispose() => _httpClient.close(force: true);

  // -------------------------------------------------------------- helpers

  /// Converts a sing-box outbound object into a node, or null when the entry
  /// is a selector/urltest/direct/block pseudo-outbound rather than a server.
  static ProxyNode? _nodeFromOutbound(
    Map<String, dynamic> outbound, {
    String? subscriptionId,
  }) {
    final type = (outbound['type'] ?? '').toString().toLowerCase();
    const skipTypes = {
      'selector',
      'urltest',
      'direct',
      'block',
      'dns',
      '', // untyped
    };
    if (skipTypes.contains(type)) return null;

    final protocol = NodeProtocol.fromTag(type);
    if (protocol == NodeProtocol.unknown) return null;

    final server = (outbound['server'] ?? '').toString();
    final port = switch (outbound['server_port']) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    if (server.isEmpty || port == 0) return null;

    final tag = (outbound['tag'] ?? '').toString();
    final raw = Map<String, dynamic>.from(outbound)
      ..remove('type')
      ..remove('tag')
      ..remove('server')
      ..remove('server_port');

    return ProxyNode(
      id: _outboundId(type, server, port, tag),
      name: tag.isNotEmpty ? tag : '$server:$port',
      protocol: protocol,
      server: server,
      serverPort: port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  static String _outboundId(
      String type, String server, int port, String tag) {
    var hash = 0x811c9dc5;
    for (final unit in '$type|$server|$port|$tag'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static bool _looksLikeJson(String text) =>
      text.startsWith('{') || text.startsWith('[');

  /// True for a plain http(s) URL with no credentials and no fragment, which
  /// distinguishes a subscription from an `http://user:pass@host` share link.
  static bool _looksLikeSubscriptionUrl(String text) {
    if (text.contains('\n')) return false;
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      return false;
    }
    final uri = Uri.tryParse(text);
    if (uri == null) return false;
    return uri.userInfo.isEmpty && uri.fragment.isEmpty;
  }

  /// Subscription bodies are usually base64 of a newline-separated link list.
  static String _maybeDecodeBase64List(String text) {
    if (text.contains('://')) return text;
    final compact = text.replaceAll(RegExp(r'\s'), '');
    if (compact.isEmpty) return text;
    if (!RegExp(r'^[A-Za-z0-9+/\-_=]+$').hasMatch(compact)) return text;
    try {
      var value = compact.replaceAll('-', '+').replaceAll('_', '/');
      final remainder = value.length % 4;
      if (remainder > 0) {
        value = value.padRight(value.length + 4 - remainder, '=');
      }
      final decoded = utf8.decode(base64.decode(value));
      return decoded.contains('://') ? decoded : text;
    } on Object {
      return text;
    }
  }

  /// Parses `upload=1; download=2; total=3; expire=1700000000`.
  static ({DateTime? expiresAt, int? usedBytes, int? totalBytes})
      _parseUserInfo(String? header) {
    if (header == null || header.isEmpty) {
      return (expiresAt: null, usedBytes: null, totalBytes: null);
    }
    int? upload;
    int? download;
    int? total;
    DateTime? expire;
    for (final part in header.split(';')) {
      final pair = part.split('=');
      if (pair.length != 2) continue;
      final key = pair[0].trim().toLowerCase();
      final value = int.tryParse(pair[1].trim());
      if (value == null) continue;
      switch (key) {
        case 'upload':
          upload = value;
        case 'download':
          download = value;
        case 'total':
          total = value;
        case 'expire':
          if (value > 0) {
            expire = DateTime.fromMillisecondsSinceEpoch(value * 1000);
          }
      }
    }
    final used = (upload ?? 0) + (download ?? 0);
    return (
      expiresAt: expire,
      usedBytes: used > 0 ? used : null,
      totalBytes: total,
    );
  }

  /// `profile-title` may be `base64:<payload>` for non-ASCII names.
  static String? _decodeHeaderTitle(String? header) {
    if (header == null || header.isEmpty) return null;
    if (!header.startsWith('base64:')) return header;
    try {
      var value = header.substring('base64:'.length);
      final remainder = value.length % 4;
      if (remainder > 0) {
        value = value.padRight(value.length + 4 - remainder, '=');
      }
      return utf8.decode(base64.decode(value));
    } on Object {
      return null;
    }
  }

  /// Strips anything URL-shaped from an error before it reaches the UI.
  static String _redact(Object error) {
    final message = error.toString();
    return message.replaceAll(RegExp(r'https?://\S+'), '<url>');
  }
}
