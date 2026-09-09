/// Picks the loopback ports a session's config will listen on.
///
/// The Clash API and the local mixed inbound used to be two fixed numbers, which
/// is fine until something else on the machine already holds one. A desktop with
/// another proxy client installed is the common case: the core then fails to
/// bind, and the user gets an engine error naming a port they never chose. So
/// the ports are chosen per start instead, and injected into the rendered config.
///
/// The fixed numbers survive as the preferred pair. Keeping them when they are
/// free means a user's own firewall rule or a bookmarked dashboard URL goes on
/// working, and only a genuine conflict moves anything.
library;

import 'dart:io';

/// The pair of loopback ports one session renders into its config.
typedef LoopbackPorts = ({int clashApiPort, int localProxyPort});

/// How a session obtains its ports, so a caller can supply them instead.
///
/// [freeLoopbackPorts] is the only implementation that ships. The indirection
/// exists for widget tests: they drive a connect through the real state layer,
/// and a genuine `ServerSocket.bind` awaited inside the test binding's fake-async
/// zone never completes, so a test that taps Connect would hang rather than fail.
typedef PortAllocator = Future<LoopbackPorts> Function({
  required int preferredClashApiPort,
  required int preferredLocalProxyPort,
});

/// One free loopback port, preferring [preferred].
///
/// Falls back to whatever the OS hands out when the preferred number is taken.
/// There is an unavoidable race between releasing the socket here and the core
/// binding it — nothing short of passing a file descriptor to the child closes
/// it, and sing-box does not take one. In practice the window is milliseconds
/// and the alternative is the conflict this exists to avoid.
Future<int> freeLoopbackPort({int preferred = 0}) async {
  if (preferred != 0 && await _isFree(preferred)) return preferred;

  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Two distinct free ports, preferring the pair the config used to hardcode.
///
/// Distinct is checked rather than assumed: the OS can hand out the same number
/// twice once the first socket is closed, and two inbounds on one port is a
/// start failure that would look like a core bug.
Future<LoopbackPorts> freeLoopbackPorts({
  required int preferredClashApiPort,
  required int preferredLocalProxyPort,
}) async {
  final clashApiPort = await freeLoopbackPort(preferred: preferredClashApiPort);
  var localProxyPort = await freeLoopbackPort(
    preferred: preferredLocalProxyPort,
  );
  // One retry is enough: the second draw cannot collide with the first unless
  // the OS reuses it immediately, and a third would only ever be theatre.
  if (localProxyPort == clashApiPort) localProxyPort = await freeLoopbackPort();

  return (clashApiPort: clashApiPort, localProxyPort: localProxyPort);
}

Future<bool> _isFree(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}
