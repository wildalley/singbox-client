/// TCP handshake latency probing.
///
/// This measures the time to open a TCP connection to the node's server,
/// which is a reasonable proxy for node responsiveness without needing the
/// tunnel to be up. It does not verify that the proxy credentials work. UDP
/// protocols are not probed here: a successful TCP connect to their port would
/// not say anything useful, and a failed connect would be a false failure.
library;

import 'dart:async';
import 'dart:io';

import '../models/node.dart';

class LatencyTester {
  const LatencyTester({this.timeout = const Duration(seconds: 3)});

  final Duration timeout;

  /// Returns latency in milliseconds, or [ProxyNode.unreachableLatency] when
  /// the connection could not be established within [timeout]. Returns `null`
  /// for protocols that do not expose a TCP service to probe.
  Future<int?> probe(ProxyNode node) async {
    if (!_supportsTcpHandshake(node.protocol)) return null;
    if (node.server.isEmpty || node.serverPort == 0) {
      return ProxyNode.unreachableLatency;
    }
    final watch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(
        node.server,
        node.serverPort,
        timeout: timeout,
      );
      watch.stop();
      return watch.elapsedMilliseconds;
    } on Object {
      return ProxyNode.unreachableLatency;
    } finally {
      try {
        socket?.destroy();
      } on Object {
        // Nothing useful to do if teardown fails.
      }
    }
  }

  /// Probes many nodes with bounded concurrency so a large subscription does
  /// not open hundreds of sockets at once. Nodes without a TCP probe are not
  /// emitted; callers should keep those rows untested for an engine URLTest.
  Stream<({String nodeId, int latencyMs})> probeAll(
    List<ProxyNode> nodes, {
    int concurrency = 8,
  }) {
    final controller = StreamController<({String nodeId, int latencyMs})>();
    var index = 0;
    var active = 0;
    var closed = false;

    void pump() {
      if (closed) return;
      while (active < concurrency && index < nodes.length) {
        final node = nodes[index++];
        active++;
        probe(node).then((latency) {
          // Leave UDP/QUIC nodes untested. They are measured by the engine's
          // URLTest once a tunnel is running; a TCP fallback would always
          // report them as unreachable.
          if (latency != null && !controller.isClosed) {
            controller.add((nodeId: node.id, latencyMs: latency));
          }
          active--;
          pump();
        });
      }
      if (active == 0 && index >= nodes.length && !controller.isClosed) {
        closed = true;
        controller.close();
      }
    }

    controller.onListen = pump;
    controller.onCancel = () {
      closed = true;
    };
    return controller.stream;
  }

  /// Protocols whose endpoint is not a TCP service. A direct TCP handshake is
  /// meaningful for the remaining protocols because their first hop is TCP,
  /// even though it still does not authenticate the proxy credentials.
  static bool _supportsTcpHandshake(NodeProtocol protocol) =>
      switch (protocol) {
        NodeProtocol.hysteria2 ||
        NodeProtocol.tuic ||
        NodeProtocol.wireguard =>
          false,
        _ => true,
      };
}
