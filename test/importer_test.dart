import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/importer.dart';
import 'package:singbox_client/models/node.dart';

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
        throwsA(isA<ImportException>()),
      );
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
