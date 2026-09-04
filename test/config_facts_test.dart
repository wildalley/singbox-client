import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/platform/config_facts.dart';

void main() {
  Map<String, dynamic> config({
    String controller = '127.0.0.1:9291',
    String secret = 'secret',
    List<Map<String, dynamic>> inbounds = const [
      {'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': 2080},
    ],
  }) =>
      {
        'experimental': {
          'clash_api': {
            'external_controller': controller,
            'secret': secret,
          },
        },
        'inbounds': inbounds,
      };

  test('extracts API, mixed port, and TUN facts from one config', () {
    final facts = ConfigFacts.parse(jsonEncode(config(
      controller: '[::1]:19091',
      inbounds: const [
        {'type': 'tun'},
        {'type': 'mixed', 'listen_port': 23117},
      ],
    )));

    expect(facts.clashPort, 19091);
    expect(facts.clashSecret, 'secret');
    expect(facts.mixedPort, 23117);
    expect(facts.hasTun, isTrue);
  });

  test('uses the builder port only when no explicit mixed port exists', () {
    expect(ConfigFacts.parse(jsonEncode(config())).mixedPort, 2080);
    expect(
      ConfigFacts.parse(jsonEncode(config(inbounds: const [
        {'type': 'tun'},
      ]))).mixedPort,
      2080,
    );
  });

  test('rejects missing control facts before a process can start', () {
    expect(
      () => ConfigFacts.parse(jsonEncode({'inbounds': []})),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => ConfigFacts.parse(jsonEncode(config(secret: ''))),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => ConfigFacts.parse(jsonEncode(config(controller: 'localhost'))),
      throwsA(isA<FormatException>()),
    );
  });
}
