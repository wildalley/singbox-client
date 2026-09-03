/// Client for the Clash-compatible API sing-box exposes.
///
/// This is the desktop counterpart to libbox's `CommandClient`. On Android the
/// engine runs in-process and reports over a JNI command socket; a supervised
/// `sing-box` binary offers no such thing, but the config already asks it for
/// `experimental.clash_api`, so the same three jobs — read the groups, switch
/// the selector, URL-test the members — go over HTTP on loopback instead.
///
/// What the two do not share is push. libbox streams group updates; the Clash
/// API answers requests and streams only counters, so the caller polls
/// [group]. Traffic is the mirror image: three separate sockets, no single
/// snapshot, which is why [traffic] merges them here rather than leaving the
/// controller to hold three sets of partial numbers.
///
/// Every request carries the config's `secret`. It is not decoration: the
/// controller can switch outbounds and read the node list, so an unauthenticated
/// listener on 127.0.0.1 would hand that to anything else on the machine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/proxy_state.dart';

/// A live JSON feed and the way to shut it down.
typedef ClashSocket = ({
  Stream<Object?> frames,
  Future<void> Function() close,
});

/// Opens one of the API's WebSocket endpoints. Injectable for tests.
typedef ClashSocketConnector = Future<ClashSocket> Function(
  Uri uri,
  Map<String, String> headers,
);

class ClashApiClient {
  ClashApiClient({
    required this.port,
    required this.secret,
    this.host = '127.0.0.1',
    http.Client? client,
    ClashSocketConnector? connector,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _connect = connector ?? _openWebSocket;

  final int port;
  final String secret;
  final String host;

  final http.Client _client;
  final bool _ownsClient;
  final ClashSocketConnector _connect;

  /// The same target the `urltest` outbound uses, so a manual test and the
  /// engine's own periodic one measure the same thing.
  static const testUrl = 'https://www.gstatic.com/generate_204';

  Map<String, String> get _headers => {
        if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
      };

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path,
        queryParameters: query,
      );

  /// The engine's version string, or null when nothing answers.
  ///
  /// Doubles as the readiness probe: the API starts listening as part of
  /// `sing-box run` coming up, so the first successful call is the earliest
  /// moment the engine is actually able to carry traffic.
  Future<String?> version() async {
    final body = await _get('/version');
    if (body == null) return null;
    final value = body['version'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Every proxy the engine knows, keyed by name.
  Future<Map<String, Map<String, Object?>>> proxies() async {
    final body = await _get('/proxies');
    final proxies = body?['proxies'];
    if (proxies is! Map) return const {};
    return {
      for (final entry in proxies.entries)
        if (entry.value is Map)
          entry.key.toString(): Map<String, Object?>.from(
            entry.value as Map,
          ),
    };
  }

  /// One group as a [ProxyGroup], or null when [tag] is not a group.
  ///
  /// Member delays come from each proxy's own `history`, which is where the
  /// engine records both its periodic `urltest` results and anything [delay]
  /// measured. A member with no history reports 0 — libbox's "no result" — so
  /// the UI cannot mistake an untested node for an instant one.
  Future<ProxyGroup?> group(String tag) async {
    final all = await proxies();
    return groupFrom(all, tag);
  }

  /// Folds an already-fetched [proxies] map into a group. Separate so a caller
  /// reading several groups pays for one request.
  static ProxyGroup? groupFrom(
    Map<String, Map<String, Object?>> proxies,
    String tag,
  ) {
    final self = proxies[tag];
    if (self == null) return null;
    final members = self['all'];
    if (members is! List) return null;
    final delays = <String, int>{};
    for (final member in members) {
      final name = member?.toString();
      if (name == null || name.isEmpty) continue;
      delays[name] = _lastDelay(proxies[name]);
    }
    return ProxyGroup(
      tag: tag,
      selected: (self['now'] ?? '').toString(),
      delays: delays,
    );
  }

  /// Points [group] at [member]. Throws on refusal, so the caller can report a
  /// failed switch instead of showing one that did not happen.
  Future<void> select(String group, String member) async {
    final response = await _client.put(
      _uri('/proxies/${Uri.encodeComponent(group)}'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'name': member}),
    );
    if (response.statusCode ~/ 100 != 2) {
      throw ClashApiException(
        'select $member: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  /// URL-tests one proxy, in milliseconds. 0 means it did not answer — a
  /// timeout, a refused connection, or a non-2xx from the test URL — matching
  /// [ProxyGroup.delays]'s "no result" so both paths read the same.
  Future<int> delay(
    String name, {
    Duration timeout = const Duration(seconds: 5),
    String url = testUrl,
  }) async {
    final body = await _get(
      '/proxies/${Uri.encodeComponent(name)}/delay',
      {'url': url, 'timeout': '${timeout.inMilliseconds}'},
    );
    final value = body?['delay'];
    return value is num ? value.toInt() : 0;
  }

  /// Merged counters, as one [ProxyTraffic] per update.
  ///
  /// The API splits what the UI shows across three endpoints: `/traffic` has
  /// the per-second rates and no totals, `/connections` the totals and the open
  /// connection count, `/memory` the resident figure. Each socket pushes about
  /// once a second on its own schedule, so the last value from each is held and
  /// a full snapshot goes out whenever any of them moves.
  ///
  /// Cancelling the subscription closes all three sockets.
  Stream<ProxyTraffic> traffic() {
    var up = 0, down = 0, upTotal = 0, downTotal = 0, count = 0, memory = 0;
    late StreamController<ProxyTraffic> controller;
    final sockets = <ClashSocket>[];

    void push() => controller.add(ProxyTraffic(
          uplink: up,
          downlink: down,
          uplinkTotal: upTotal,
          downlinkTotal: downTotal,
          // The Clash API counts connections without a direction; the UI's two
          // slots come from libbox. Reporting the same number in both would
          // read as twice the connections, so only inbound is filled.
          connectionsIn: count,
          memory: memory,
        ));

    Future<void> open() async {
      for (final (path, handler) in <(String, void Function(Map<String, Object?>))>[
        ('/traffic', (frame) {
          up = _int(frame['up']);
          down = _int(frame['down']);
        }),
        ('/connections', (frame) {
          upTotal = _int(frame['uploadTotal']);
          downTotal = _int(frame['downloadTotal']);
          final connections = frame['connections'];
          count = connections is List ? connections.length : 0;
          // Present on sing-box, absent on some Clash implementations; the
          // /memory socket below is the primary source either way.
          final inline = _int(frame['memory']);
          if (inline > 0) memory = inline;
        }),
        ('/memory', (frame) => memory = _int(frame['inuse'])),
      ]) {
        final socket = await _connect(_uri(path), _headers);
        sockets.add(socket);
        socket.frames.listen(
          (frame) {
            final decoded = _decode(frame);
            if (decoded == null) return;
            handler(decoded);
            push();
          },
          // One endpoint going away should not take the other two with it:
          // the engine closing /memory still leaves rates worth showing.
          onError: (Object _) {},
          cancelOnError: false,
        );
      }
    }

    Future<void> shut() async {
      for (final socket in sockets) {
        try {
          await socket.close();
        } on Object {
          // Already gone.
        }
      }
      sockets.clear();
    }

    controller = StreamController<ProxyTraffic>(
      onListen: () => open().onError((error, _) {
        if (!controller.isClosed) controller.addError(error ?? 'socket failed');
      }),
      onCancel: shut,
    );
    return controller.stream;
  }

  Future<Map<String, Object?>?> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    try {
      final response = await _client.get(_uri(path, query), headers: _headers);
      if (response.statusCode ~/ 100 != 2) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on Object {
      // Not listening yet, gone, or answering with something that is not JSON.
      // Every caller has a meaningful answer for "no data", so none of them
      // benefits from an exception here.
      return null;
    }
  }

  /// Releases the HTTP client, when this object made it.
  void dispose() {
    if (_ownsClient) _client.close();
  }

  static int _lastDelay(Map<String, Object?>? proxy) {
    final history = proxy?['history'];
    if (history is! List || history.isEmpty) return 0;
    final last = history.last;
    return last is Map ? _int(last['delay']) : 0;
  }

  static Map<String, Object?>? _decode(Object? frame) {
    if (frame is! String) return null;
    try {
      final decoded = jsonDecode(frame);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  static Future<ClashSocket> _openWebSocket(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws').toString(),
      headers: headers,
    );
    return (frames: socket, close: socket.close);
  }
}

class ClashApiException implements Exception {
  const ClashApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ClashApiException: $message';
}
