/// [ProxyTraffic.connections], which reconciles two runtimes that disagree.
///
/// The desktop dashboard showed a flat zero for open connections through every
/// release that had the field, because the two sources fill different slots and
/// the card read the one the desktop leaves empty. The counters themselves were
/// right and tested; nothing asserted the number the card takes from them. These
/// pin both platform shapes to the reading.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/models/proxy_state.dart';

void main() {
  group('connections', () {
    test('reads the Clash API shape, which fills only the inbound slot', () {
      // What `/connections` produces: the length of an undirected list, with
      // nothing to put in the outbound slot. The desktop's only shape.
      expect(const ProxyTraffic(connectionsIn: 7).connections, 7);
    });

    test('reads the libbox shape, which fills both', () {
      // Both directions reported separately, and near-equal in practice because
      // an inbound connection dials a matching outbound.
      expect(
        const ProxyTraffic(connectionsIn: 12, connectionsOut: 11).connections,
        12,
      );
    });

    test('does not double a libbox reading', () {
      // The reason this is a maximum and not a sum. Adding the two would report
      // 24 connections for the 12 the user has, while still being right on the
      // desktop — so a sum looks correct exactly where it is not checked.
      expect(
        const ProxyTraffic(connectionsIn: 12, connectionsOut: 12).connections,
        12,
      );
    });

    test('takes whichever slot carries the reading', () {
      // Neither field is privileged: a runtime that reports only outbound is
      // read the same way as one that reports only inbound.
      expect(const ProxyTraffic(connectionsOut: 5).connections, 5);
    });

    test('is zero when neither is reported', () {
      // Idle, and the state the card shows before the first frame arrives.
      expect(ProxyTraffic.zero.connections, 0);
    });

    test('survives the platform channel round trip', () {
      // Android arrives as a map over the method channel, so the getter has to
      // hold for a value that was decoded rather than constructed.
      final decoded = ProxyTraffic.fromMap(const {
        'connectionsIn': 3,
        'connectionsOut': 4,
      });

      expect(decoded.connections, 4);
    });
  });
}
