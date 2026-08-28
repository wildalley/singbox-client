import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/share_link_parser.dart';
import 'package:singbox_client/models/node.dart';

void main() {
  group('vmess', () {
    test('decodes a base64 payload into a ws+tls outbound', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'v': '2',
        'ps': 'Tokyo Fast',
        'add': 'example.com',
        'port': '443',
        'id': '11111111-2222-3333-4444-555555555555',
        'aid': '0',
        'net': 'ws',
        'path': '/ray',
        'host': 'cdn.example.com',
        'tls': 'tls',
        'sni': 'sni.example.com',
      })));

      final node = ShareLinkParser.parse('vmess://$payload');

      expect(node.name, 'Tokyo Fast');
      expect(node.protocol, NodeProtocol.vmess);
      expect(node.server, 'example.com');
      expect(node.serverPort, 443);
      expect(node.raw['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(node.raw['tls']['server_name'], 'sni.example.com');
      expect(node.raw['transport']['type'], 'ws');
      expect(node.raw['transport']['path'], '/ray');
      expect(node.raw['transport']['headers']['Host'], 'cdn.example.com');
    });

    test('rejects a payload without the required fields', () {
      final payload = base64.encode(utf8.encode(jsonEncode({'ps': 'broken'})));
      expect(
        () => ShareLinkParser.parse('vmess://$payload'),
        throwsA(isA<ShareLinkParseException>()),
      );
    });
  });

  test('vless reality carries the public key and short id', () {
    final node = ShareLinkParser.parse(
      'vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@example.com:8443'
      '?security=reality&sni=www.apple.com&pbk=PUBKEY&sid=ab12&flow=xtls-rprx-vision'
      '&type=grpc&serviceName=grpcsvc#Reality%20Node',
    );

    expect(node.name, 'Reality Node');
    expect(node.protocol, NodeProtocol.vless);
    expect(node.raw['flow'], 'xtls-rprx-vision');
    expect(node.raw['tls']['reality']['public_key'], 'PUBKEY');
    expect(node.raw['tls']['reality']['short_id'], 'ab12');
    expect(node.raw['transport']['service_name'], 'grpcsvc');
  });

  test('trojan maps sni and insecure', () {
    final node = ShareLinkParser.parse(
      'trojan://secret@example.com:443?sni=cover.example.com&allowInsecure=1#T',
    );

    expect(node.protocol, NodeProtocol.trojan);
    expect(node.raw['password'], 'secret');
    expect(node.raw['tls']['server_name'], 'cover.example.com');
    expect(node.raw['tls']['insecure'], true);
  });

  group('shadowsocks', () {
    test('parses SIP002 with base64 userinfo', () {
      final userInfo =
          base64.encode(utf8.encode('aes-256-gcm:hunter2')).replaceAll('=', '');
      final node = ShareLinkParser.parse('ss://$userInfo@example.com:8388#SS');

      expect(node.protocol, NodeProtocol.shadowsocks);
      expect(node.raw['method'], 'aes-256-gcm');
      expect(node.raw['password'], 'hunter2');
      expect(node.server, 'example.com');
      expect(node.serverPort, 8388);
    });

    test('parses plain userinfo and an IPv6 host', () {
      final node = ShareLinkParser.parse(
        'ss://aes-128-gcm:pw@[2001:db8::1]:8388#v6',
      );

      expect(node.server, '2001:db8::1');
      expect(node.serverPort, 8388);
      expect(node.raw['method'], 'aes-128-gcm');
    });

    test('parses the fully base64-encoded legacy form', () {
      final body = base64.encode(
        utf8.encode('chacha20-ietf-poly1305:pw@example.com:1234'),
      );
      final node = ShareLinkParser.parse('ss://$body');

      expect(node.server, 'example.com');
      expect(node.serverPort, 1234);
      expect(node.raw['method'], 'chacha20-ietf-poly1305');
    });
  });

  test('hysteria2 keeps obfs settings and defaults the port', () {
    final node = ShareLinkParser.parse(
      'hysteria2://pw@example.com?obfs=salamander&obfs-password=ob#H2',
    );

    expect(node.protocol, NodeProtocol.hysteria2);
    expect(node.serverPort, 443);
    expect(node.raw['obfs']['type'], 'salamander');
    expect(node.raw['obfs']['password'], 'ob');
  });

  test('tuic splits uuid and password', () {
    final node = ShareLinkParser.parse(
      'tuic://uuid-value:pass-value@example.com:443'
      '?congestion_control=bbr&udp_relay_mode=native#TU',
    );

    expect(node.raw['uuid'], 'uuid-value');
    expect(node.raw['password'], 'pass-value');
    expect(node.raw['congestion_control'], 'bbr');
  });

  test('unsupported schemes are rejected', () {
    expect(
      () => ShareLinkParser.parse('ftp://example.com'),
      throwsA(isA<ShareLinkParseException>()),
    );
    expect(
      () => ShareLinkParser.parse('not-a-link'),
      throwsA(isA<ShareLinkParseException>()),
    );
  });

  group('parseMany', () {
    test('keeps good links and counts the bad ones', () {
      final result = ShareLinkParser.parseMany('''
trojan://a@one.example.com:443#One
# a comment line
garbage://nope
trojan://b@two.example.com:443#Two
''');

      expect(result.nodes.map((node) => node.name), ['One', 'Two']);
      expect(result.skipped, 1);
    });

    test('assigns the subscription id to every node', () {
      final result = ShareLinkParser.parseMany(
        'trojan://a@one.example.com:443#One',
        subscriptionId: 'sub-1',
      );

      expect(result.nodes.single.subscriptionId, 'sub-1');
    });
  });

  test('ids are stable across re-imports but differ per server', () {
    const link = 'trojan://pw@example.com:443#Name';
    final first = ShareLinkParser.parse(link);
    final second = ShareLinkParser.parse(link);
    final other = ShareLinkParser.parse('trojan://pw@other.example.com:443#N');

    expect(first.id, second.id);
    expect(first.id, isNot(other.id));
  });
}
