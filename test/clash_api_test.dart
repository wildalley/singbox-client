/// The Clash API client, against a real HTTP server on loopback.
///
/// This is the whole of the desktop control path: every node switch, latency
/// figure and counter the Linux runtime shows comes through here. A real server
/// rather than a stubbed `http.Client` because half of what can go wrong is in
/// the request itself — the wrong path, an unencoded group name, a missing
/// `Authorization` header — and a stub that is handed the URI it expects proves
/// none of it.
///
/// The WebSocket side takes an injected connector instead: what matters there is
/// the merge of three feeds into one snapshot, not the handshake.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:singbox_client/platform/clash_api.dart';

/// One request the server saw.
class _Seen {
  _Seen(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

void main() {
  late HttpServer server;
  late List<_Seen> seen;

  /// Per-path handler. Anything unhandled is a 404, which is also what an
  /// endpoint this build of sing-box does not serve looks like.
  late Map<String, void Function(HttpRequest)> routes;

  setUp(() async {
    seen = [];
    routes = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      seen.add(_Seen(
        request.method,
        request.uri,
        {
          for (final name in const ['authorization', 'content-type'])
            if (request.headers.value(name) case final value?) name: value,
        },
        body,
      ));
      final handler = routes[request.uri.path];
      if (handler == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        handler(request);
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  /// Serves [json] at [path] with a 200.
  void serve(String path, Object? json) {
    routes[path] = (request) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(json));
    };
  }

  ClashApiClient client({String secret = 's3cret'}) => ClashApiClient(
        port: server.port,
        secret: secret,
        host: server.address.address,
      );

  group('version', () {
    test('reads the version string', () async {
      serve('/version', {'version': '1.13.21'});

      expect(await client().version(), '1.13.21');
    });

    test('is null when nothing is listening', () async {
      // The readiness poll leans on this: before the engine binds, the connection
      // is refused, and that has to read as "not ready" rather than throw.
      // The client has to be built while the port is still readable — a closed
      // HttpServer will not tell you what it was bound to.
      final api = client();
      await server.close(force: true);

      expect(await api.version(), isNull);
    });

    test('is null on an error status or an empty version', () async {
      expect(await client().version(), isNull, reason: '404');

      serve('/version', {'version': ''});
      expect(await client().version(), isNull, reason: 'empty');

      serve('/version', {'meta': true});
      expect(await client().version(), isNull, reason: 'absent');
    });

    test('is null when the body is not JSON', () async {
      routes['/version'] = (request) => request.response.write('<html>nope');

      expect(await client().version(), isNull);
    });
  });

  group('auth', () {
    test('every request carries the secret as a bearer token', () async {
      serve('/version', {'version': '1.13.21'});
      serve('/proxies', {'proxies': <String, Object?>{}});

      final api = client();
      await api.version();
      await api.proxies();

      expect(seen, hasLength(2));
      for (final request in seen) {
        expect(request.headers['authorization'], 'Bearer s3cret',
            reason: '${request.uri.path} went out unauthenticated');
      }
    });

    test('no header at all when the config has no secret', () async {
      // Not a case the app renders, but the client is also pointed at whatever
      // the user's own config says, and an empty `Bearer ` is not the same as
      // sending nothing.
      serve('/version', {'version': '1.13.21'});

      await client(secret: '').version();

      expect(seen.single.headers.containsKey('authorization'), isFalse);
    });
  });

  group('proxies', () {
    test('keys every proxy by name', () async {
      serve('/proxies', {
        'proxies': {
          'proxy': {'type': 'Selector', 'now': 'Tokyo'},
          'Tokyo': {'type': 'Trojan'},
        },
      });

      final proxies = await client().proxies();

      expect(proxies.keys, containsAll(['proxy', 'Tokyo']));
      expect(proxies['proxy']!['now'], 'Tokyo');
    });

    test('skips entries that are not objects, and empty on a bad shape',
        () async {
      serve('/proxies', {
        'proxies': {
          'ok': {'type': 'Trojan'},
          'junk': 'not an object',
        },
      });
      expect((await client().proxies()).keys, ['ok']);

      serve('/proxies', {'proxies': []});
      expect(await client().proxies(), isEmpty);

      serve('/proxies', {});
      expect(await client().proxies(), isEmpty);
    });
  });

  group('group', () {
    test('reads the selection and each member delay from history', () async {
      serve('/proxies', {
        'proxies': {
          'proxy': {
            'type': 'Selector',
            'now': 'Osaka',
            'all': ['Tokyo', 'Osaka'],
          },
          'Tokyo': {
            'history': [
              {'delay': 300},
              {'delay': 142},
            ],
          },
          'Osaka': {
            'history': [
              {'delay': 88},
            ],
          },
        },
      });

      final group = await client().group('proxy');

      expect(group, isNotNull);
      expect(group!.tag, 'proxy');
      expect(group.selected, 'Osaka');
      // The last entry, not the first: history grows, and the newest result is
      // the one the UI should show.
      expect(group.delays, {'Tokyo': 142, 'Osaka': 88});
    });

    test('an untested member reports 0 rather than being dropped', () async {
      // 0 is libbox's "no result", and the UI reads it as such. Omitting the
      // member instead would make it look like it left the group.
      serve('/proxies', {
        'proxies': {
          'proxy': {'now': 'Tokyo', 'all': ['Tokyo', 'Osaka', 'Seoul']},
          'Tokyo': {'history': <Object?>[]},
          'Osaka': {'history': 'nonsense'},
        },
      });

      final group = await client().group('proxy');

      expect(group!.delays, {'Tokyo': 0, 'Osaka': 0, 'Seoul': 0});
    });

    test('is null for a proxy that is not a group, or an unknown tag', () async {
      serve('/proxies', {
        'proxies': {
          'Tokyo': {'type': 'Trojan'},
        },
      });

      expect(await client().group('Tokyo'), isNull, reason: 'no members');
      expect(await client().group('nope'), isNull, reason: 'unknown');
    });

    test('groupFrom folds an already-fetched map, so one fetch serves many',
        () async {
      final proxies = {
        'proxy': <String, Object?>{'now': 'Tokyo', 'all': ['Tokyo']},
        'auto': <String, Object?>{'now': 'Tokyo', 'all': ['Tokyo']},
        'Tokyo': <String, Object?>{
          'history': [
            {'delay': 42},
          ],
        },
      };

      expect(ClashApiClient.groupFrom(proxies, 'proxy')!.delays, {'Tokyo': 42});
      expect(ClashApiClient.groupFrom(proxies, 'auto')!.selected, 'Tokyo');
      expect(ClashApiClient.groupFrom(proxies, 'Tokyo'), isNull);
    });
  });

  group('select', () {
    test('PUTs the member name to the group', () async {
      routes['/proxies/proxy'] = (request) {};

      await client().select('proxy', 'Tokyo');

      final request = seen.single;
      expect(request.method, 'PUT');
      expect(request.uri.path, '/proxies/proxy');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {'name': 'Tokyo'});
    });

    test('encodes a group name that is not URL-safe', () async {
      // Group tags are config-supplied. An unencoded space or slash would
      // either 404 or address a different path entirely.
      routes['/proxies/my%20group'] = (request) {};

      await client().select('my group', 'Tokyo');

      expect(seen.single.uri.path, '/proxies/my%20group',
          reason: 'the space travels encoded');
      expect(seen.single.uri.pathSegments, ['proxies', 'my group'],
          reason: 'and decodes back to the tag the config named');
    });

    test('throws on a refusal, so a failed switch is not shown as done',
        () async {
      routes['/proxies/proxy'] =
          (request) => request.response.statusCode = HttpStatus.badRequest;

      await expectLater(
        client().select('proxy', 'Tokyo'),
        throwsA(isA<ClashApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('delay', () {
    test('asks for the same URL the urltest outbound uses', () async {
      // A manual test and the engine's own periodic one have to measure the
      // same thing, or sorting by latency reorders on every refresh.
      serve('/proxies/Tokyo/delay', {'delay': 142});

      final delay = await client().delay('Tokyo');

      expect(delay, 142);
      expect(seen.single.uri.queryParameters['url'], ClashApiClient.testUrl);
      expect(seen.single.uri.queryParameters['timeout'], '5000');
    });

    test('passes a custom timeout in milliseconds', () async {
      serve('/proxies/Tokyo/delay', {'delay': 10});

      await client().delay('Tokyo', timeout: const Duration(seconds: 2));

      expect(seen.single.uri.queryParameters['timeout'], '2000');
    });

    test('0 when the node did not answer', () async {
      // The API reports a timeout as an error status with no delay, and the UI
      // reads 0 as "no result" — the same value an untested member carries.
      expect(await client().delay('Tokyo'), 0, reason: '404');

      serve('/proxies/Tokyo/delay', {'message': 'timeout'});
      expect(await client().delay('Tokyo'), 0, reason: 'no delay field');
    });

    test('encodes the proxy name', () async {
      serve('/proxies/Tokyo%20%C2%B7%2001/delay', {'delay': 7});

      expect(await client().delay('Tokyo · 01'), 7);
    });
  });

  group('traffic', () {
    /// A connector backed by one controller per path.
    ({
      ClashSocketConnector connect,
      Map<String, StreamController<Object?>> feeds,
      List<String> closed,
    }) fakeSockets() {
      final feeds = <String, StreamController<Object?>>{};
      final closed = <String>[];
      Future<ClashSocket> connect(Uri uri, Map<String, String> headers) async {
        final feed = feeds[uri.path] = StreamController<Object?>();
        return (
          frames: feed.stream,
          close: () async {
            closed.add(uri.path);
            await feed.close();
          },
        );
      }

      return (connect: connect, feeds: feeds, closed: closed);
    }

    test('merges the three feeds into one snapshot', () async {
      final sockets = fakeSockets();
      final api = ClashApiClient(
        port: server.port,
        secret: 's3cret',
        connector: sockets.connect,
      );
      final snapshots = <dynamic>[];
      final subscription = api.traffic().listen(snapshots.add);
      await pumpEventQueue();

      sockets.feeds['/traffic']!.add(jsonEncode({'up': 100, 'down': 2000}));
      await pumpEventQueue();
      sockets.feeds['/memory']!.add(jsonEncode({'inuse': 4096}));
      await pumpEventQueue();
      sockets.feeds['/connections']!.add(jsonEncode({
        'uploadTotal': 10000,
        'downloadTotal': 90000,
        'connections': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      }));
      await pumpEventQueue();

      // One push per frame, each carrying everything seen so far: the sockets
      // tick on their own schedules, so a snapshot must not drop the other two.
      expect(snapshots, hasLength(3));
      final last = snapshots.last;
      expect(last.uplink, 100);
      expect(last.downlink, 2000);
      expect(last.uplinkTotal, 10000);
      expect(last.downlinkTotal, 90000);
      expect(last.memory, 4096);
      expect(last.connectionsIn, 2);
      // The API counts connections without a direction; filling both slots
      // would read as twice the connections.
      expect(last.connectionsOut, 0);

      await subscription.cancel();
    });

    test('subscribes with the secret, to all three endpoints', () async {
      final sockets = fakeSockets();
      final api = ClashApiClient(
        port: server.port,
        secret: 's3cret',
        connector: (uri, headers) {
          expect(headers['Authorization'], 'Bearer s3cret');
          return sockets.connect(uri, headers);
        },
      );

      final subscription = api.traffic().listen((_) {});
      await pumpEventQueue();

      expect(sockets.feeds.keys, containsAll(['/traffic', '/connections', '/memory']));

      await subscription.cancel();
    });

    test('cancelling closes every socket', () async {
      final sockets = fakeSockets();
      final api = ClashApiClient(
        port: server.port,
        secret: '',
        connector: sockets.connect,
      );

      final subscription = api.traffic().listen((_) {});
      await pumpEventQueue();
      await subscription.cancel();

      expect(sockets.closed, hasLength(3));
    });

    test('one feed failing leaves the others reporting', () async {
      // The engine closing /memory still leaves rates worth showing.
      final sockets = fakeSockets();
      final api = ClashApiClient(
        port: server.port,
        secret: '',
        connector: sockets.connect,
      );
      final snapshots = <dynamic>[];
      final subscription = api.traffic().listen(snapshots.add);
      await pumpEventQueue();

      sockets.feeds['/memory']!.addError('gone');
      await pumpEventQueue();
      sockets.feeds['/traffic']!.add(jsonEncode({'up': 5, 'down': 6}));
      await pumpEventQueue();

      expect(snapshots, hasLength(1));
      expect(snapshots.single.uplink, 5);

      await subscription.cancel();
    });

    test('ignores frames that are not JSON objects', () async {
      final sockets = fakeSockets();
      final api = ClashApiClient(
        port: server.port,
        secret: '',
        connector: sockets.connect,
      );
      final snapshots = <dynamic>[];
      final subscription = api.traffic().listen(snapshots.add);
      await pumpEventQueue();

      sockets.feeds['/traffic']!.add('not json');
      sockets.feeds['/traffic']!.add(jsonEncode([1, 2]));
      sockets.feeds['/traffic']!.add(const [1, 2, 3]);
      await pumpEventQueue();

      expect(snapshots, isEmpty);

      await subscription.cancel();
    });

    test('reports a failure to open rather than hanging silently', () async {
      final api = ClashApiClient(
        port: server.port,
        secret: '',
        connector: (uri, headers) async => throw const SocketException('refused'),
      );

      await expectLater(api.traffic(), emitsError(isA<SocketException>()));
    });
  });

  test('dispose only closes a client it made itself', () async {
    // The controller keeps one client for its whole run and hands it in; if
    // dispose closed that, every later request would throw on a dead client.
    serve('/version', {'version': '1.13.21'});
    final shared = http.Client();
    addTearDown(shared.close);

    ClashApiClient(port: server.port, secret: '', client: shared).dispose();

    expect(
      await ClashApiClient(port: server.port, secret: '', client: shared)
          .version(),
      '1.13.21',
    );
  });
}
