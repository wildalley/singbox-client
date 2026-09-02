# SingBox Client architecture

## Layers

```
lib/ui          Screens and widgets. Reads AppState, never touches the runtime.
lib/state       AppState: the single ChangeNotifier the UI binds to.
lib/data        Import, parsing, config rendering, persistence, latency probing.
lib/models      Plain data: nodes, subscriptions, settings, runtime state.
lib/platform    ProxyController: the boundary to native code.
lib/l10n        ARB sources plus generated localizations (en, zh).
android/…/kotlin  VpnService, libbox glue, method/event channels.
```

The UI depends on nothing below `lib/state`. Process IDs, VPN permissions,
system routes, and service lifecycles live behind `ProxyController`.

## Runtime boundary

```dart
abstract interface class ProxyController {
  Stream<ProxyState> get states;
  Stream<ProxyTraffic> get traffic;
  Stream<ProxyLogEntry> get logs;
  Stream<ProxyGroup> get groups;

  ProxyState get currentState;

  Future<bool> requestPermission();
  Future<void> start(String configJson);
  Future<void> stop();
  Future<void> clearLogs();
  Future<void> reload(String configJson);
  Future<void> selectOutbound(String outboundTag);
  Future<void> urlTest();
  Future<String?> coreVersion();

  void dispose();
}
```

`ProxyState.stage` makes permission, starting, connected, stopping,
disconnected, and error states explicit. `createProxyController()` returns
`AndroidProxyController` on Android and `UnsupportedProxyController` elsewhere,
so the UI, import pipeline, and config rendering stay usable on platforms whose
runtime is not implemented yet.

## Platform adapters

**Android — implemented.** `SingBoxVpnService` (a `VpnService`) owns the tunnel
lifecycle and the foreground notification. libbox drives the proxy:

- `Libbox.newCommandServer(...)` → `startOrReloadService(config)` parses the
  config and opens the tun.
- `BoxPlatform` implements libbox's `PlatformInterface`. Its `openTun` translates
  libbox's `TunOptions` into a `VpnService.Builder` and returns the raw fd.
- `Libbox.newCommandClient(...)` subscribes to the status, log, and outbound-group
  streams. The group subscription is what carries each member's `URLTestDelay`,
  so it is the only source of a latency measured *through* the proxy rather than
  a TCP handshake to its server address. The disconnected fallback only probes
  TCP-based protocols; Hysteria2, TUIC, and WireGuard stay untested until the
  engine is running because their UDP ports cannot be meaningfully checked with
  a TCP connect.
- Log output is bounded at both sides of the bridge: `BoxEvents` forwards at
  most 60 lines per second and reports suppressed lines, while `AppState`
  retains the latest 500 entries and batches UI notifications. `clearLogs`
  clears both the visible list and libbox's in-memory command log buffer; stale
  callbacks are ignored after a failed start or stop.
- `BoxEvents` holds state as process-global truth, because the service outlives
  the Flutter engine when the user swipes the app away. `MainActivity` attaches
  a listener and replays the current status when a new engine connects.

Channels: `singbox/control` (methods) and `singbox/events` (status, traffic,
logs, outbound groups).

**Windows / Linux — not implemented.** Planned as a supervised `sing-box`
process with TUN integration, plus a system-proxy / firewall flow on Windows and
systemd/polkit handling on Linux. Process stdout/stderr must be parsed into
structured, redacted events. Keep the UI usable when the service is unavailable
and report actionable permission errors.

## Configuration flow

1. Import a share link, subscription URL, sing-box JSON, or a file
   (`lib/data/importer.dart`, `lib/data/share_link_parser.dart`).
2. Parse into `ProxyNode`s. Each node keeps its original outbound body in `raw`,
   so re-rendering never drops fields this app does not model.
3. Render a full sing-box 1.13 config (`lib/data/config_builder.dart`): typed
   DNS servers, rule `action` verbs, one `address` list on the TUN inbound.
4. Pass the rendered JSON to the controller; consume state, traffic, and log
   streams back.

Node ids are a hash of protocol, host, port, and secret, so re-importing a
subscription preserves latency readings and favourites.

Outbound tags are generated in exactly one place — `ConfigBuilder.outboundTag` —
because runtime node switching (`selectOutbound`) has to name the same tag the
config declared, and because it is the only mapping that leads from a tag the
engine reports back to a node: URL-test delays arrive keyed by tag.

## Secrets

Subscription tokens, UUIDs, passwords, and private keys must stay out of logs,
crash reports, clipboard previews, and error messages. Concretely:

- `Subscription.redactedUrl` strips credentials and query strings for display.
- Import errors run through `_redact`, which replaces anything URL-shaped.
- The generated-config viewer warns before the config is copied, because it
  contains credentials in full — except the Clash API token, which it masks,
  because a config preview is something users screenshot.

The Clash API listener is a secret of its own. It stays enabled because libbox
reads its traffic figures from it, so it is bound to loopback and gated behind a
128-bit `Random.secure()` token persisted in `Storage`: on Android every app on
the device can reach `127.0.0.1`, and an unauthenticated controller would let any
of them switch the user's outbound or read their connection list.
`ConfigBuilder.build` takes that token as a required argument with no default, so
a caller cannot forget it and quietly render an open listener.

## Remaining work

- Desktop process supervision and privileged TUN / system-proxy operations.
- Per-app proxy UI (the setting and config plumbing exist; there is no picker).
- Release signing: `android/app/build.gradle.kts` still signs with debug keys.
- Additional ABIs — `scripts/build-libbox.sh` builds arm64 only by default.
