/// The per-start loopback port draw, against real sockets.
///
/// The point of the allocator is that a machine where another proxy client
/// already holds 9291 or 2080 still connects. So the two cases worth pinning are
/// the ones a user actually hits: nothing is listening and the documented
/// numbers are kept — their firewall rule and bookmarked dashboard URL go on
/// working — or something is, and the start quietly moves off it instead of
/// handing them an engine error naming a port they never chose.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/config_builder.dart';
import 'package:singbox_client/data/port_allocator.dart';

/// Binds [port] on loopback, or skips the test when the machine running the
/// suite already has it taken — which is the very situation under test, and not
/// something a test can arrange twice.
Future<ServerSocket?> _hold(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    addTearDown(socket.close);
    return socket;
  } on SocketException {
    markTestSkipped('port $port is already in use');
    return null;
  }
}

void main() {
  group('freeLoopbackPort', () {
    test('keeps the preferred number when it is free', () async {
      // Held and released, so the number is known to be bindable a moment ago
      // without the probe inside the allocator racing this test for it.
      final probe = await _hold(0);
      if (probe == null) return;
      final port = probe.port;
      await probe.close();

      expect(await freeLoopbackPort(preferred: port), port);
    });

    test('moves off a port something else holds', () async {
      final held = await _hold(0);
      if (held == null) return;

      final port = await freeLoopbackPort(preferred: held.port);

      expect(port, isNot(held.port));
      expect(port, greaterThan(0));
    });

    test('with no preference, asks the OS', () async {
      // 0 is the sentinel, never a returned port: the whole call would be
      // pointless if the ephemeral draw could come back as "let the OS choose".
      expect(await freeLoopbackPort(), greaterThan(0));
    });
  });

  group('freeLoopbackPorts', () {
    test('prefers the documented pair', () async {
      final api = await _hold(ConfigBuilder.defaultClashApiPort);
      if (api == null) return;
      final proxy = await _hold(ConfigBuilder.defaultLocalProxyPort);
      if (proxy == null) return;
      await api.close();
      await proxy.close();

      final ports = await freeLoopbackPorts(
        preferredClashApiPort: ConfigBuilder.defaultClashApiPort,
        preferredLocalProxyPort: ConfigBuilder.defaultLocalProxyPort,
      );

      expect(ports.clashApiPort, ConfigBuilder.defaultClashApiPort);
      expect(ports.localProxyPort, ConfigBuilder.defaultLocalProxyPort);
    });

    test('replaces only the port that is taken', () async {
      final api = await _hold(0);
      if (api == null) return;
      final proxy = await _hold(0);
      if (proxy == null) return;
      final freeProxyPort = proxy.port;
      await proxy.close();

      final ports = await freeLoopbackPorts(
        preferredClashApiPort: api.port,
        preferredLocalProxyPort: freeProxyPort,
      );

      expect(ports.clashApiPort, isNot(api.port));
      expect(ports.localProxyPort, freeProxyPort,
          reason: 'a free preference must survive the other one moving');
    });

    test('never hands both inbounds the same port', () async {
      // Two inbounds on one port is a start failure that would read as a core
      // bug, so the pair is checked for distinctness rather than assumed: the OS
      // is free to hand out the same ephemeral number twice once the first
      // probe socket has closed.
      for (var i = 0; i < 20; i++) {
        final ports = await freeLoopbackPorts(
          preferredClashApiPort: 0,
          preferredLocalProxyPort: 0,
        );
        expect(ports.clashApiPort, isNot(ports.localProxyPort));
      }
    });
  });
}
