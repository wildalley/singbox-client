import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/data/importer.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/models/subscription.dart';

void main() {
  late Importer importer;

  setUp(() => importer = Importer());
  tearDown(() => importer.dispose());

  group('sing-box JSON', () {
    test('extracts server outbounds and skips pseudo-outbounds', () {
      final config = jsonEncode({
        'outbounds': [
          {
            'type': 'trojan',
            'tag': 'Tokyo',
            'server': 'jp.example.com',
            'server_port': 443,
            'password': 'secret',
          },
          {
            'type': 'selector',
            'tag': 'proxy',
            'outbounds': ['Tokyo']
          },
          {'type': 'direct', 'tag': 'direct'},
        ],
      });

      final result = importer.importSingBoxConfig(config);

      expect(result.nodes, hasLength(1));
      expect(result.nodes.single.name, 'Tokyo');
      expect(result.nodes.single.protocol, NodeProtocol.trojan);
      // The selector and direct entries are skipped, not failures.
      expect(result.skipped, 2);
    });

    test('keeps protocol fields in raw so the outbound re-renders intact', () {
      final config = jsonEncode({
        'outbounds': [
          {
            'type': 'vless',
            'tag': 'V',
            'server': 'a.example.com',
            'server_port': 443,
            'uuid': 'abc',
            'flow': 'xtls-rprx-vision',
            'tls': {'enabled': true, 'server_name': 'a.example.com'},
          },
        ],
      });

      final node = importer.importSingBoxConfig(config).nodes.single;
      final outbound = node.toOutbound('t');

      expect(outbound['uuid'], 'abc');
      expect(outbound['flow'], 'xtls-rprx-vision');
      expect(outbound['tls'], isA<Map>());
      expect(outbound['tag'], 't');
    });

    test('accepts a bare outbounds array', () {
      final config = jsonEncode([
        {
          'type': 'shadowsocks',
          'tag': 'S',
          'server': 'a.example.com',
          'server_port': 8388,
          'method': 'aes-256-gcm',
          'password': 'p',
        },
      ]);

      expect(importer.importSingBoxConfig(config).nodes, hasLength(1));
    });

    test('accepts a single outbound object', () {
      final config = jsonEncode({
        'type': 'trojan',
        'tag': 'T',
        'server': 'a.example.com',
        'server_port': 443,
        'password': 'p',
      });

      expect(importer.importSingBoxConfig(config).nodes, hasLength(1));
    });

    test('rejects invalid JSON', () {
      expect(
        () => importer.importSingBoxConfig('{not json'),
        throwsA(isA<ImportException>()),
      );
    });

    test('rejects a config with no usable outbounds', () {
      final config = jsonEncode({
        'outbounds': [
          {'type': 'direct', 'tag': 'direct'},
        ],
      });

      expect(
        () => importer.importSingBoxConfig(config),
        throwsA(isA<ImportException>()),
      );
    });

    test('skips outbounds missing a server or port', () {
      final config = jsonEncode({
        'outbounds': [
          {
            'type': 'trojan',
            'tag': 'ok',
            'server': 'a.com',
            'server_port': 443
          },
          {'type': 'trojan', 'tag': 'no-port', 'server': 'b.com'},
        ],
      });

      final result = importer.importSingBoxConfig(config);
      expect(result.nodes, hasLength(1));
      expect(result.skipped, 1);
    });
  });

  group('share links', () {
    test('imports a plain newline separated list', () {
      const links = 'trojan://pass@a.example.com:443#A\n'
          'trojan://pass@b.example.com:443#B';

      final result = importer.importShareLinks(links);
      expect(result.nodes.map((node) => node.name), ['A', 'B']);
    });

    test('unwraps a base64 encoded list', () {
      const links = 'trojan://pass@a.example.com:443#A\n'
          'trojan://pass@b.example.com:443#B';
      final encoded = base64.encode(utf8.encode(links));

      final result = importer.importShareLinks(encoded);
      expect(result.nodes, hasLength(2));
    });

    test('counts unparseable lines as skipped', () {
      const links = 'trojan://pass@a.example.com:443#A\n'
          'garbage://nope\n'
          'not a link at all';

      final result = importer.importShareLinks(links);
      expect(result.nodes, hasLength(1));
      expect(result.skipped, 2);
    });

    test('throws when nothing could be parsed', () {
      expect(
        () => importer.importShareLinks('garbage://nope'),
        throwsA(isA<ImportException>()),
      );
    });
  });

  group('format detection', () {
    test('treats JSON text as a config', () async {
      final config = jsonEncode({
        'outbounds': [
          {
            'type': 'trojan',
            'tag': 'T',
            'server': 'a.example.com',
            'server_port': 443,
            'password': 'p',
          },
        ],
      });

      final result = await importer.importText(config);
      expect(result.nodes.single.name, 'T');
    });

    test('treats share links as links, not as a subscription URL', () async {
      // An http:// share link carries credentials, so it must not be fetched.
      final result =
          await importer.importText('trojan://p@a.example.com:443#T');
      expect(result.nodes.single.name, 'T');
    });

    test('rejects empty input', () {
      expect(() => importer.importText('   '), throwsA(isA<ImportException>()));
    });

    test('rejects a non-http subscription URL', () {
      expect(
        () => importer.fetchSubscription('ftp://example.com/sub'),
        throwsA(isA<ImportException>().having(
          (error) => error.failure,
          'failure',
          SubscriptionFailure.badSource,
        )),
      );
    });
  });

  /// Against a real server on loopback: what the UI ends up saying depends on
  /// how a failure is classified, and the reported bug was that it said it in
  /// English because the exception message *was* the message.
  group('a subscription over HTTP', () {
    late HttpServer server;
    late String url;
    late void Function(HttpResponse response) respond;

    setUp(() async {
      respond = (response) => response.write(
            'trojan://pass@a.example.com:443#A',
          );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // A token in the query, because it must never reach a message.
      url = 'http://${server.address.address}:${server.port}/sub?token=s3cr3t';
      server.listen((request) async {
        respond(request.response);
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('parses a link list body', () async {
      final result = await importer.fetchSubscription(url);
      expect(result.nodes.single.name, 'A');
    });

    test('an error status is reported as a status, with the code', () async {
      respond = (response) {
        response.statusCode = HttpStatus.forbidden;
        response.write('nope');
      };

      await expectLater(
        importer.fetchSubscription(url),
        throwsA(isA<ImportException>()
            .having((error) => error.failure, 'failure',
                SubscriptionFailure.httpStatus)
            .having((error) => error.statusCode, 'statusCode', 403)),
      );
    });

    test('a body with nothing usable in it is not a transport failure',
        () async {
      // The distinction the user acts on: this one will not be fixed by
      // connecting first and trying again.
      respond = (response) => response.write('<html>login</html>');

      await expectLater(
        importer.fetchSubscription(url),
        throwsA(isA<ImportException>().having((error) => error.failure,
            'failure', SubscriptionFailure.unusableContent)),
      );
    });

    test('rejects an oversized response before parsing it', () async {
      final body = List<String>.filled(4 * 1024 * 1024 + 1, 'x').join();
      respond = (response) => response.write(body);

      await expectLater(
        importer.fetchSubscription(url),
        throwsA(isA<ImportException>().having(
          (error) => error.failure,
          'failure',
          SubscriptionFailure.responseTooLarge,
        )),
      );
    });

    test('limits concurrent subscription fetches', () async {
      var active = 0;
      var peak = 0;
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      url = 'http://${server.address.address}:${server.port}/sub';
      server.listen((request) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        request.response.write('trojan://pass@a.example.com:443#A');
        await request.response.close();
        active--;
      });

      await Future.wait([
        for (var i = 0; i < 8; i++) importer.fetchSubscription(url),
      ]);

      expect(peak, lessThanOrEqualTo(3));
    });

    test('nothing listening reads as unreachable, without the token', () async {
      final port = server.port;
      await server.close(force: true);

      await expectLater(
        importer.fetchSubscription(
          'http://127.0.0.1:$port/sub?token=s3cr3t',
        ),
        throwsA(isA<ImportException>()
            .having((error) => error.failure, 'failure',
                SubscriptionFailure.unreachable)
            .having((error) => error.message, 'message',
                isNot(contains('s3cr3t')))),
      );
    });

    test('connected, it tries the tunnel first and then the direct path',
        () async {
      // The app is excluded from the VPN, so the loopback inbound is the only
      // way to reach a blocked panel — and a panel that refuses proxied clients
      // only answers directly. Here nothing is behind the inbound, which is
      // what a running engine with an unreachable node looks like.
      final ServerSocket inbound;
      try {
        inbound = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          ConfigBuilder.localProxyPort,
        );
      } on SocketException {
        markTestSkipped('port ${ConfigBuilder.localProxyPort} is in use');
        return;
      }
      addTearDown(() => inbound.close());
      var attempts = 0;
      inbound.listen((socket) {
        attempts++;
        socket.destroy();
      });

      final result = await importer.fetchSubscription(url, viaLocalProxy: true);

      expect(attempts, greaterThan(0), reason: 'the tunnel was not tried');
      expect(result.nodes.single.name, 'A',
          reason: 'the direct path must still be attempted after it fails');
    });
  });

  test('ids are stable across re-imports so latency and favourites survive',
      () {
    const link = 'trojan://pass@a.example.com:443#A';
    final first = importer.importShareLinks(link).nodes.single;
    final second = importer.importShareLinks(link).nodes.single;

    expect(first.id, second.id);
  });
}
