/// The exit-address lookup, and where the app decides to run one.
///
/// Two things here are load-bearing rather than cosmetic. The reply is parsed
/// from a third-party service that is free to change it and that answers a
/// rate-limit page with HTTP 200, so the parser has to refuse a body it does not
/// understand instead of putting its error text on the dashboard as an address.
/// And the request has to leave through the tunnel when one is up, because the
/// whole point of the reading is to say whether the tunnel is carrying traffic —
/// sent directly it reports the user's own line and claims the tunnel is doing
/// nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:singbox_client/data/ip_lookup.dart';
import 'package:singbox_client/data/storage.dart';
import 'package:singbox_client/models/node.dart';
import 'package:singbox_client/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, node;

/// An [AppState] wired to [lookup], with [nodes] already stored.
Future<AppState> stateWith(
  FakeIpLookup lookup, {
  List<ProxyNode> nodes = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  if (nodes.isNotEmpty) await storage.writeNodes(nodes);
  return AppState(
    storage: storage,
    controller: FakeProxyController(),
    ipLookup: lookup,
  );
}

/// Answers from memory, and records how it was asked.
class FakeIpLookup extends IpLookup {
  FakeIpLookup({this.answer, this.onFetch});

  ExitAddress? answer;

  /// Called before answering, for a test that needs to observe the timing.
  final void Function()? onFetch;

  final calls = <bool>[];
  var disposed = false;

  @override
  Future<ExitAddress?> fetch({required bool viaLocalProxy}) async {
    calls.add(viaLocalProxy);
    onFetch?.call();
    return answer;
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  group('parseEcho', () {
    test('reads the primary service', () {
      // api.ip.sb/geoip, trimmed to the fields that are used.
      final address = IpLookup.parseEcho(
        '{"ip":"203.0.113.7","country":"Singapore","country_code":"sg",'
        '"city":"Singapore"}',
      );

      expect(address?.ip, '203.0.113.7');
      // Upper-cased here so the badge does not depend on which service answered.
      expect(address?.countryCode, 'SG');
      expect(address?.countryName, 'Singapore');
    });

    test('reads the fallback service, which names the field differently', () {
      // ifconfig.co/json says country_iso where the other says country_code.
      final address = IpLookup.parseEcho(
        '{"ip":"198.51.100.9","country":"Japan","country_iso":"JP"}',
      );

      expect(address?.ip, '198.51.100.9');
      expect(address?.countryCode, 'JP');
    });

    test('keeps an address that came with no country', () {
      // Only the address is required: a reading without a country still answers
      // the question the row exists for.
      final address = IpLookup.parseEcho('{"ip":"192.0.2.1"}');

      expect(address?.ip, '192.0.2.1');
      expect(address?.countryCode, isNull);
      expect(address?.countryName, isNull);
    });

    test('reads an IPv6 address', () {
      expect(IpLookup.parseEcho('{"ip":"2001:db8::1"}')?.ip, '2001:db8::1');
    });

    test('refuses a rate-limit page, which is also valid JSON', () {
      // The reason the address is checked rather than trusted. ipinfo.io answers
      // this with a 200 in some cases, and taking `error.title` for an address
      // would put "Rate limit hit" on the dashboard looking like a result.
      expect(
        IpLookup.parseEcho(
          '{"status":429,"error":{"title":"Rate limit hit"}}',
        ),
        isNull,
      );
    });

    test('refuses a body whose ip is not an address', () {
      // A captive portal or a changed schema, either of which would otherwise be
      // shown verbatim as though the lookup had worked.
      expect(IpLookup.parseEcho('{"ip":"unavailable"}'), isNull);
      expect(IpLookup.parseEcho('{"ip":"1.2.3"}'), isNull);
      expect(IpLookup.parseEcho('{"ip":42}'), isNull);
    });

    test('refuses what is not JSON, or not an object', () {
      // An HTML error page, or a service that answers a bare string.
      expect(IpLookup.parseEcho('<html>nope</html>'), isNull);
      expect(IpLookup.parseEcho('"203.0.113.7"'), isNull);
      expect(IpLookup.parseEcho(''), isNull);
    });

    test('ignores a blank country rather than showing an empty badge', () {
      final address = IpLookup.parseEcho('{"ip":"192.0.2.1","country_code":" "}');

      expect(address?.countryCode, isNull);
    });
  });

  group('AppState', () {
    test('a lookup while connected goes through the tunnel', () async {
      // The one assertion that matters for correctness: routed directly this
      // reports the user's own address on Android and in desktop system-proxy
      // mode, so a working tunnel would read as no tunnel at all.
      final lookup = FakeIpLookup(
        answer: const ExitAddress(ip: '203.0.113.7', countryCode: 'SG'),
      );
      final state = await stateWith(lookup, nodes: [node('a', 'Tokyo')]);
      addTearDown(state.dispose);

      await state.connect();
      await pumpEventQueue();

      expect(lookup.calls, isNotEmpty, reason: 'connecting did not look it up');
      expect(lookup.calls.last, isTrue, reason: 'not routed through the tunnel');
      expect(state.exitAddress?.ip, '203.0.113.7');
    });

    test('disconnecting clears the address instead of re-checking', () async {
      // The address belongs to the tunnel's exit. Once the tunnel is down the
      // honest reading is none — and going out to ask would hand a third party
      // the user's real address to answer a question they never asked.
      final lookup = FakeIpLookup(
        answer: const ExitAddress(ip: '203.0.113.7'),
      );
      final state = await stateWith(lookup, nodes: [node('a', 'Tokyo')]);
      addTearDown(state.dispose);

      await state.connect();
      await pumpEventQueue();
      expect(state.exitAddress, isNotNull);
      final before = lookup.calls.length;

      await state.disconnect();
      await pumpEventQueue();

      expect(state.exitAddress, isNull);
      expect(lookup.calls, hasLength(before), reason: 'asked anyway');
    });

    test('a failed lookup clears the reading rather than keeping a stale one',
        () async {
      final lookup = FakeIpLookup(
        answer: const ExitAddress(ip: '203.0.113.7'),
      );
      final state = await stateWith(lookup, nodes: [node('a', 'Tokyo')]);
      addTearDown(state.dispose);

      await state.connect();
      await pumpEventQueue();
      expect(state.exitAddress, isNotNull);

      // The service stops answering — rate-limited, or the exit went dark.
      lookup.answer = null;
      await state.refreshExitAddress();

      // A stale address beside a tunnel that has since moved reads as a working
      // check, which is worse than admitting this one did not answer.
      expect(state.exitAddress, isNull);
    });

    test('overlapping refreshes put one request on the wire', () async {
      // Switching nodes a few times in a row triggers one of these each. Without
      // the guard that is one outbound request per tap.
      final lookup = FakeIpLookup(
        answer: const ExitAddress(ip: '203.0.113.7'),
      );
      final state = await stateWith(lookup);
      addTearDown(state.dispose);

      await Future.wait([
        state.refreshExitAddress(),
        state.refreshExitAddress(),
        state.refreshExitAddress(),
      ]);

      expect(lookup.calls, hasLength(1));
    });

    test('a lookup while disconnected goes direct', () async {
      // The manual refresh on the row stays enabled while disconnected, which is
      // how a user checks their own address. That one must not be sent to a
      // loopback port with nothing behind it.
      final lookup = FakeIpLookup(answer: const ExitAddress(ip: '192.0.2.1'));
      final state = await stateWith(lookup);
      addTearDown(state.dispose);

      await state.refreshExitAddress();

      expect(lookup.calls, [isFalse]);
    });

    test('disposing the state disposes the lookup', () async {
      final lookup = FakeIpLookup();
      final state = await stateWith(lookup);

      state.dispose();

      expect(lookup.disposed, isTrue);
    });
  });
}
