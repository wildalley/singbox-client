/// Tests for the region code the node rows show.
///
/// Subscriptions carry no structured region, so the code is inferred from the
/// node name. The stakes are asymmetric: a wrong flag tells the user their
/// traffic exits a country it does not, while showing nothing just falls back to
/// a neutral icon. So these tests care as much about the names that must yield
/// null as the ones that must resolve.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/models/node.dart';

void main() {
  String? codeOf(String name) => ProxyNode(
        id: 'n',
        name: name,
        protocol: NodeProtocol.vless,
        server: 'example.com',
        serverPort: 443,
      ).regionCode;

  group('regionCode', () {
    test('decodes a flag emoji to its region code', () {
      expect(codeOf('🇯🇵 Tokyo 01'), 'JP');
      expect(codeOf('🇭🇰 香港'), 'HK');
      expect(codeOf('Premium 🇸🇬'), 'SG');
    });

    test('a flag wins over the text beside it', () {
      // The flag is explicit; the surrounding words are a guess. When a name
      // carries both, trust the flag.
      expect(codeOf('🇹🇼 relay via japan'), 'TW');
    });

    test('reads locations written in Chinese', () {
      expect(codeOf('香港 01'), 'HK');
      expect(codeOf('日本东京 IEPL'), 'JP');
      expect(codeOf('美国洛杉矶 02'), 'US');
      expect(codeOf('新加坡专线'), 'SG');
    });

    test('handles both simplified and traditional forms', () {
      expect(codeOf('臺灣 01'), 'TW');
      expect(codeOf('台湾 01'), 'TW');
      expect(codeOf('韓國 01'), 'KR');
      expect(codeOf('韩国 01'), 'KR');
    });

    test('a longer Chinese name wins over the shorter one inside it', () {
      // 印度尼西亚 contains 印度; matching in list order keeps Indonesia from
      // being reported as India.
      expect(codeOf('印度尼西亚 01'), 'ID');
      expect(codeOf('印度孟买'), 'IN');
    });

    test('reads locations spelled out in Latin letters', () {
      expect(codeOf('Japan 01'), 'JP');
      expect(codeOf('Frankfurt Node'), 'DE');
      expect(codeOf('amsterdam-relay'), 'NL');
    });

    test('separators and case do not matter to a spelled name', () {
      expect(codeOf('US-Los Angeles-01'), 'US');
      expect(codeOf('los_angeles'), 'US');
      expect(codeOf('LOSANGELES'), 'US');
      expect(codeOf('New York 03'), 'US');
    });

    test('reads a bare region code token', () {
      expect(codeOf('HK 01'), 'HK');
      expect(codeOf('jp-relay-2'), 'JP');
      expect(codeOf('node.sg.01'), 'SG');
    });

    test('maps the alternate codes that appear in node names', () {
      expect(codeOf('UK London'), 'GB');
      expect(codeOf('USA 01'), 'US');
    });

    test('a bare code must be a whole token, not a substring', () {
      // `russia` contains `us`, and reporting Russia as the US would be a
      // meaningful lie about where traffic exits.
      expect(codeOf('russia 01'), 'RU');
      expect(codeOf('Moscow'), 'RU');
    });

    test('returns null when the name carries no location', () {
      expect(codeOf('Premium Node 01'), isNull);
      expect(codeOf('relay-fast-3'), isNull);
      expect(codeOf(''), isNull);
      expect(codeOf('高速中转'), isNull);
    });

    test('always returns two uppercase letters when it returns anything', () {
      const names = [
        '🇯🇵 Tokyo',
        '香港 01',
        'Frankfurt',
        'uk-london',
        'USA 01',
      ];
      for (final name in names) {
        final code = codeOf(name);
        expect(code, isNotNull, reason: name);
        expect(code, matches(RegExp(r'^[A-Z]{2}$')), reason: name);
      }
    });
  });
}
