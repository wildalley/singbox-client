import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/data/latency_tester.dart';
import 'package:singbox_client/models/node.dart';

void main() {
  const tester = LatencyTester();

  test('does not TCP-probe UDP and QUIC protocols', () async {
    for (final protocol in [
      NodeProtocol.hysteria2,
      NodeProtocol.tuic,
      NodeProtocol.wireguard,
    ]) {
      final node = ProxyNode(
        id: protocol.tag,
        name: protocol.label,
        protocol: protocol,
        server: '198.51.100.1',
        serverPort: 1,
      );

      expect(await tester.probe(node), isNull,
          reason: '${protocol.label} has no TCP handshake to measure');
    }
  });

  test('probeAll leaves UDP and QUIC nodes untested', () async {
    final node = ProxyNode(
      id: 'hy2',
      name: 'Hysteria2',
      protocol: NodeProtocol.hysteria2,
      server: '198.51.100.1',
      serverPort: 46428,
    );

    expect(await tester.probeAll([node]).toList(), isEmpty);
  });
}
