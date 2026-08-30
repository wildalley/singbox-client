/// Replaces the unpacked rule-sets with fresh copies from upstream.
///
/// This is the other half of shipping the lists inside the app (see
/// `rule_sets.dart`): bundling fixes start, updating fixes staleness. The one
/// rule it exists to honour is that it must never sit on the start path — the
/// engine reads the files off disk, and a download that fails, hangs, or is
/// offline has to cost nothing but a stale list.
///
/// Two consequences of where the fetch runs:
///
///  * The app's own package is excluded from the tunnel, so an in-app request
///    goes out on the direct path even while connected (see `local_proxy.dart`).
///    For the audience these CN lists are for, that path cannot reach
///    raw.githubusercontent.com — hence [update]'s `viaLocalProxy`, which sends
///    the download through the config's loopback `mixed` inbound and out the
///    selected node.
///  * sing-box reads a `local` rule-set when it starts, so a list downloaded
///    now takes effect at the next connect, not immediately.
library;

import 'dart:io';
import 'dart:typed_data';

import 'local_proxy.dart';
import 'rule_sets.dart';

class RuleSetUpdateException implements Exception {
  RuleSetUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RuleSetUpdater {
  RuleSetUpdater({HttpClient? httpClient, this.base = BundledRuleSets.upstreamBase})
      : _httpClient = httpClient ?? (HttpClient()..connectionTimeout = _timeout);

  final HttpClient _httpClient;

  /// Upstream root. Overridden in tests to serve the same paths locally.
  final String base;

  static const _timeout = Duration(seconds: 20);
  static const _userAgent = 'sing-box; SingBoxClient/0.1.0';

  /// A compiled list is tens of KB; anything this large is not one, and the cap
  /// keeps a wrong URL from filling the phone before the magic check runs.
  static const _maxBytes = 8 << 20;

  /// Downloads every rule-set into [dir], replacing each file atomically.
  ///
  /// A tag that fails leaves its old file in place, and the whole call throws so
  /// the caller can report it; the tags that did succeed keep their new bytes.
  /// The install record is only stamped when all of them landed, so a partial
  /// run is retried rather than remembered as current.
  Future<RuleSetInstall> update(
    Directory dir, {
    bool viaLocalProxy = false,
  }) async {
    // Set per call: whether the tunnel is up decides the path, and the same
    // updater outlives several connects.
    routeHttp(_httpClient, viaLocalProxy: viaLocalProxy);
    await dir.create(recursive: true);

    final failed = <String>[];
    for (final tag in BundledRuleSets.tags) {
      try {
        await _fetchInto(dir, tag);
      } on Object {
        failed.add(tag);
      }
    }

    if (failed.isNotEmpty) {
      throw RuleSetUpdateException(
        'Could not update ${failed.join(', ')}',
      );
    }
    return BundledRuleSets.markDownloaded(dir);
  }

  Future<void> _fetchInto(Directory dir, String tag) async {
    final bytes = await _get(BundledRuleSets.upstreamUrl(tag, base: base));

    // A 200 is not proof of a rule-set: a proxy error page and a captive-portal
    // login both arrive as content, and would only fail on the device, at start,
    // as an unreadable rule-set.
    if (bytes.length < 1024 ||
        String.fromCharCodes(bytes.take(3)) != BundledRuleSets.magic) {
      throw RuleSetUpdateException('$tag: not a compiled rule-set');
    }

    // Write beside the target and rename: the file the config points at is
    // never half-written, even if the process dies mid-download.
    final target = File('${dir.path}/${BundledRuleSets.fileName(tag)}');
    final staging = File('${target.path}.new');
    try {
      await staging.writeAsBytes(bytes, flush: true);
      await staging.rename(target.path);
    } on Object {
      if (staging.existsSync()) staging.deleteSync();
      rethrow;
    }
  }

  Future<Uint8List> _get(Uri url) async {
    final request = await _httpClient.getUrl(url).timeout(_timeout);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) {
      // Drain, or the connection is held until the client is closed.
      await response.drain<void>();
      throw RuleSetUpdateException('HTTP ${response.statusCode}');
    }

    final builder = BytesBuilder(copy: false);
    await response.forEach((chunk) {
      if (builder.length + chunk.length > _maxBytes) {
        throw RuleSetUpdateException('response too large');
      }
      builder.add(chunk);
    }).timeout(_timeout);
    return builder.takeBytes();
  }

  void dispose() => _httpClient.close(force: true);
}
