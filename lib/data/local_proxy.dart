/// How the app's own HTTP requests leave the device.
///
/// This is counter-intuitive enough to be worth one place: while connected, the
/// app's own traffic does **not** go through the tunnel. `BoxPlatform.kt` calls
/// `addDisallowedApplication(service.packageName)` — without it a subscription
/// fetch would loop back into a proxy that is not up yet. So a host the user
/// cannot reach directly stays unreachable after connecting, unless the request
/// is aimed at the config's loopback `mixed` inbound, which is the one path from
/// in-app HTTP out through the selected node.
///
/// Both fetchers that face the network use this: the rule-set updater and the
/// subscription importer.
library;

import 'dart:io';

import 'config_builder.dart';

/// Where a request is sent, as `HttpClient.findProxy` spells it.
///
/// [localProxyPort] has to be the port the running config actually listens on,
/// which is not knowable from here: a start whose preferred port was taken
/// renders a different one. Null falls back to the preferred number, for the
/// callers that have no session to ask — a fetch made while disconnected takes
/// the direct path anyway, so the value is unused there. Nullable rather than
/// defaulted so the fetchers can pass a session's port straight through without
/// each of them having to name the fallback.
String localProxyDirective({
  required bool viaLocalProxy,
  int? localProxyPort,
}) =>
    viaLocalProxy
        ? 'PROXY 127.0.0.1:'
            '${localProxyPort ?? ConfigBuilder.defaultLocalProxyPort}'
        : 'DIRECT';

/// Points [client] at the tunnel or at the direct path.
///
/// Set per request rather than once per client: whether the tunnel is up decides
/// the path, and these clients outlive several connects — which is also why the
/// port is an argument, since a later connect can land on a different one.
void routeHttp(
  HttpClient client, {
  required bool viaLocalProxy,
  int? localProxyPort,
}) =>
    client.findProxy = (_) => localProxyDirective(
          viaLocalProxy: viaLocalProxy,
          localProxyPort: localProxyPort,
        );
