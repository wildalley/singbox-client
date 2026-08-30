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
/// The port is [ConfigBuilder.localProxyPort] rather than a literal: it has to
/// be the port the rendered config actually listens on.
String localProxyDirective({required bool viaLocalProxy}) => viaLocalProxy
    ? 'PROXY 127.0.0.1:${ConfigBuilder.localProxyPort}'
    : 'DIRECT';

/// Points [client] at the tunnel or at the direct path.
///
/// Set per request rather than once per client: whether the tunnel is up decides
/// the path, and these clients outlive several connects.
void routeHttp(HttpClient client, {required bool viaLocalProxy}) =>
    client.findProxy = (_) => localProxyDirective(viaLocalProxy: viaLocalProxy);
