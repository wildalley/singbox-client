# SingBox Client architecture

## Layers

```
lib/ui          Screens and widgets. Reads AppState, never touches the runtime.
lib/state       AppState: the single ChangeNotifier the UI binds to.
lib/data        Import, parsing, config rendering, persistence, latency probing.
lib/models      Plain data: nodes, subscriptions, settings, runtime state.
lib/platform    ProxyController: the boundary to native code. Plus the desktop
                shell — tray, window, single instance — which sits beside it
                rather than in lib/ui, because it runs before the first frame.
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

  Future<void> shutdown();

  void dispose();
}
```

`shutdown` exists because `dispose` cannot do its job. Disposing is synchronous:
it can signal the engine but not wait for it, and it cannot restore the desktop's
proxy settings at all, since that is an async call out to `gsettings`. Quitting
through `dispose` alone while connected in system-proxy mode therefore leaves the
whole desktop pointed at a port with nothing behind it. So the quit path awaits
`shutdown` — stop the engine, put the settings back, then exit — and `dispose`
stays the last resort for a teardown that cannot wait. On Android it is
deliberately a no-op beyond `dispose`: the tunnel belongs to a foreground service
with its own lifecycle, and closing the window is not a reason to drop the VPN.

`ProxyState.stage` makes permission, starting, connected, stopping,
disconnected, and error states explicit. `createProxyController()` returns
`AndroidProxyController` on Android, `LinuxProxyController` on Linux,
`WindowsProxyController` on Windows, and `UnsupportedProxyController` elsewhere,
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

**Windows — implemented.** `WindowsProxyController` writes the rendered config to
a per-run file, starts the checksum-pinned `sing-box.exe`, and waits for its Clash
API before reporting `connected`. Its stdout/stderr, `/connections` counters,
selector API, and URL-test API feed the same streams as Android.

Two modes are supported:

1. **System proxy** (default): The controller removes the TUN inbound, keeps or
   adds a mixed inbound on `127.0.0.1:2080`, and sets the WinINet registry to point
   at it. The Windows runner saves the user's proxy/PAC registry values, sets the
   loopback proxy, and restores them on stop or the next launch after a crash. No
   elevation required.

2. **TUN** (requires administrator): When a TUN inbound is present and the process
   is running elevated, the controller keeps the TUN inbound and lets sing-box
   create a Wintun virtual adapter. If not elevated, a UAC prompt requests
   administrator rights and restarts the app; the elevated instance continues
   the pending connection. The pinned sing-box runtime embeds its Wintun DLL.

The core process is attached to a native Job Object with `KILL_ON_JOB_CLOSE`, so
closing the runner also reaps a child left behind by a Dart shutdown.

**Linux — implemented.** `libbox.aar` is a gomobile artifact with JNI bindings,
so it cannot be loaded here. `LinuxProxyController` supervises an installed
`sing-box` instead and drives it over the Clash API the rendered config already
enables:

- `sing-box run -c config.json -D <workdir>` runs as a child process. The config
  is written to the XDG data dir, mode 0600 in a 0700 directory, because it holds
  node credentials and the API secret.
- The controller parses the `configJson` string it is handed to recover the Clash
  port and secret, the mixed inbound's port, and whether a tun is present. So the
  `ProxyController` interface needs no Linux-shaped additions.
- Readiness is `GET /version` polled until it answers, short-circuited if the
  child has already exited. Node switching is `PUT /proxies/{group}`, latency is
  `GET /proxies/{name}/delay` per member, and traffic, connections, and memory
  come from the three WebSockets.
- The API pushes no group updates and offers no live reload, so group state is
  polled and `reload` is stop-then-start.
- stdout/stderr stream into the log page; the last 20 lines are appended to a
  start failure, so a config the engine rejects is readable.

Two modes, because a tun here needs `CAP_NET_ADMIN` and Android's dialog has no
Linux equivalent. `ProxyMode.systemProxy` is the default: it renders no tun at
all and points the desktop at the loopback inbound — `gsettings` under GNOME,
`kwriteconfig6/5` under KDE — which needs no privileges. The previous settings
are restored on stop, and on next launch if the process was killed.

`ProxyMode.tun` renders the config Android uses, and pays for it with one
authorization. Before spawning the engine, `start` reads the binary's file
capabilities with `getcap`; if they are absent it emits
`ProxyStage.requestingPermission` and runs `pkexec setcap
cap_net_admin,cap_net_raw+ep <binary>`, which is the same polkit dialog the
desktop uses for mounting a disk. The kernel applies file capabilities at
`execve`, and the controller spawns `sing-box` as its own child, so one attribute
on one file is the whole mechanism — nothing elevates the app, and no privileged
helper is installed. Two consequences: a package upgrade replaces the binary and
the prompt comes back, and only a `sing-box` under a system prefix is eligible,
since the path can arrive from `SINGBOX_BINARY` and an elevated `setcap` against
an arbitrary path would be a capability grant on a file of the caller's choosing.
A declined or unavailable prompt reports the `setcap` line instead.

Android ignores `ProxyMode` and always renders a tun: its VpnService has nothing
else to carry, and the settings page offers no second mode there. That check
lives in `ConfigBuilder.build`, whose `tunOnly` parameter defaults to
`Platform.isAndroid`.

The three failures the app can diagnose itself — no binary, too old, no
capability — travel as an `EngineProblem` marker inside `ProxyState.message`,
which the UI turns into a translated sentence naming the fix. Engine output
passes through as-is.

## Desktop shell

`lib/platform/desktop_shell.dart` owns the tray icon, what the window's close
button means, and the quit path. It is created in `main` before `runApp` and
listens to `AppState` directly, so nothing in `lib/ui` knows a tray exists.

The ordering inside it is load-bearing, and the reason is a bug this code now
guards against. `tray_manager`'s Linux plugin implements four methods —
`destroy`, `setIcon`, `setTitle`, `setContextMenu` — and lets `setToolTip` and
`popUpContextMenu` fall through to `not_implemented`, where they throw
`MissingPluginException`. A `setToolTip` placed before `setContextMenu` therefore
threw, the menu was never set, and the close button hid the only window behind an
icon that could open nothing. Hence: the menu goes on first, nothing optional runs
before it, and `_trayPainted` records that it succeeded. Hiding the window is
gated on that flag, so a tray that failed to install leaves the close button
meaning quit rather than trapping the process.

Pointer events are absent for the same reason — an AppIndicator hands the menu to
the panel, which opens it itself, so the application is never told about a click.
On Linux the menu is the only entry point, which is why "show window" is its first
item rather than something a left click would have covered. The tray is also
redrawn only when the status it displays changes: `AppState` notifies once a
second while traffic flows, and rebuilding an open appindicator menu closes it
under the user's cursor.

Because the close button hides, a second launch is not an error to refuse — it is
the user asking for the window, most likely because the tray icon is unreachable.
`SingleInstance` binds a Unix socket in the app's own 0700 data directory on
POSIX, and a deterministic loopback TCP port on Windows because Dart does not
support Unix sockets there. A second process connects, says so, and exits, and
the first raises its window. A local endpoint rather than a lock file answers
both questions at once: whether anyone is home and how to talk to them. If
neither connecting nor binding works the app runs unguarded, since the failure
that matters is a user with no window, not a user with two.

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

### Route rules

The rendered `route.rules` list is ordered, and sing-box takes the first match, so
position is behaviour rather than presentation. From the top: `sniff`, so domain
rules can match TLS/HTTP hostnames; the clash-mode overrides and the LAN bypass;
then the user's own rules; then the bundled rule-sets.

The user's rules sit above the bundled lists because a rule someone typed for one
domain is a more specific answer than a list of millions, and below the overrides
because those are not opinions about a destination — clash-mode is a global switch
the user just flipped, and the LAN bypass keeps local traffic off the tunnel.
They render one entry each, in the user's order, rather than merging rules that
share a matcher and target: merging would be smaller but would reorder them, and
first-match-wins means the order on screen has to be the order in the config.

`CustomRule.problem` validates before rendering, and the invalid are dropped in
`ConfigBuilder` rather than at the call site. That filter is load-bearing. Ports
are `uint16` in sing-box's schema while every other matcher is a string list, so a
port rendered as `["443"]` fails at decode — `cannot unmarshal string into Go
value of type uint16` — and the whole tunnel refuses to start over one quoted
number, with nothing in the error naming the rule responsible. Editing a rule
reloads a running tunnel, which costs the live connections; that is the honest
price of changing where traffic goes, and it is the only way a rule applies now
rather than at the next connect.

### Notifications and the log

`AppState` is one `ChangeNotifier` for the whole app, which makes how often it
fires a design constraint. Two things bound it. Log lines arrive in bursts — one
per connection at debug level — so notification is coalesced through a
zero-duration `Timer`: a macrotask, deliberately, because stream events are
delivered as microtasks and a microtask scheduled from inside a listener
interleaves with the deliveries still queued behind it, turning 300 lines into 301
notifications. The buffer itself is a `RingBuffer`, a fixed-capacity `List` view,
so an append is O(1) and reads hand out the buffer rather than a copy — the naive
shape paid O(n) twice per line, exactly when lines arrived fastest.

Above that, `MaterialApp` subscribes to a `ValueNotifier` carrying only the theme
mode and locale, and the shell's chrome to one carrying only `isConnected`, so a
traffic sample no longer rebuilds `Theme`, `Localizations`, and every page beneath
them. Each page subscribes for itself through `PageBody`.

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

- Per-app proxy UI (the setting and config plumbing exist; there is no picker).
- Release signing: `android/app/build.gradle.kts` still signs with debug keys.
- Additional ABIs — `scripts/build-libbox.sh` builds arm64 only by default.
- A setting for the exit-IP lookup, which currently always runs on connect.
- Desktop paths verified against fakes but not a live session: the tray on a
  panel, the polkit prompt, the hide/show cycle.
