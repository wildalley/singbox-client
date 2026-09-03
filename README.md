# SingBox Client

A Flutter sing-box client for **Android**, **Linux**, and **Windows**. The
interface follows the Google Stitch **Obsidian Signal** design system, in dark
and light variants, with English and Chinese localization.

All three platforms run the proxy, by different means. Android embeds the
engine: a Kotlin `VpnService` drives sing-box through a self-built
`libbox.aar`. Linux supervises an installed `sing-box` binary and drives it over
its Clash API, because `libbox.aar` is Android-only and a desktop tun needs a
capability no in-process library can grant itself. Windows supervises a bundled
`sing-box.exe` the same way. Windows system-proxy mode exposes its loopback mixed
proxy through WinINet; TUN mode uses sing-box's embedded Wintun support and UAC
elevation.

## Features

**Proxy runtime (Android)**

- Foreground `VpnService` owning the VPN lifecycle, with a notification and a
  stop action
- sing-box v1.13 driven through `CommandServer` / `CommandClient`
- Live status, traffic counters, and a bounded, clearable log stream in the UI
- Runtime node switching via the `selector` outbound, without restarting the
  tunnel
- `urltest` group as a selectable exit, so the engine can pick the fastest node
  itself
- The tunnel survives the Flutter engine being killed; reopening the app
  reattaches to the running service
- Routing rule-sets ship inside the APK, so a start needs no network; stale ones
  update themselves once the tunnel is up

**Proxy runtime (Windows)**

- A checksum-pinned `sing-box.exe` is supervised beside the Flutter executable
- Supervises the bundled core over its Clash API: node switching, per-node URL
  tests, traffic, connection count, and memory
- Two modes. System proxy is the default and needs no privileges; it points
  WinINet at the loopback inbound automatically. TUN captures everything and
  asks for administrator rights through a UAC prompt; its optional System HTTP
  proxy setting can also expose that loopback inbound to WinINet applications.
  The pinned sing-box runtime carries its Wintun support, so no separate
  `wintun.dll` copy is required
- Restores the user's previous WinINet proxy settings on stop, on quit, and on
  next launch after an unclean exit
- Job object supervision: when the UI closes unexpectedly, the process supervisor
  reaps the supervised process
- Process output, Clash API traffic counters, selector changes, and URL tests
  feed the same bounded UI streams as Android

**Proxy runtime (Linux)**

- Supervises an installed `sing-box` (≥ 1.12), driven over its Clash API: node
  switching, per-node URL tests, traffic, connection count, and memory
- Two modes. System proxy is the default and needs no privileges at all, pointing
  GNOME or KDE at the loopback inbound; TUN captures everything and asks for
  `CAP_NET_ADMIN` through a polkit prompt, once per binary
- Restores the desktop's previous proxy settings on stop, on quit, and on next
  launch after an unclean exit
- Engine stdout/stderr streams into the log page, so a failed start is readable
  rather than silent
- Missing binary, too-old binary, and a tun the kernel refused are each reported
  with the fix, in the user's language

**Desktop shell**

Shared by Linux and Windows.

- Tray icon reflecting connection state, with show/hide, connect/disconnect, and
  a checked proxy-mode group in its menu
- Closing the window hides it and leaves the tunnel running; it falls back to
  quitting when no tray icon could be installed, so the window is never hidden
  behind an icon that cannot bring it back
- Quitting stops the engine and restores the desktop proxy settings before the
  process exits, rather than leaving the machine pointed at a dead port
- A second launch raises the first instance's window instead of starting a
  process whose engine cannot bind its ports

**Import**

- Subscription URL, including `subscription-userinfo` quota and expiry
- Share links: vless, vmess, trojan, shadowsocks, hysteria2, tuic, anytls,
  socks, http — with reality, uTLS, and ws/grpc/h2/httpupgrade transports
- sing-box JSON config, whole file or a bare `outbounds` array
- Config file from disk

Node ids are derived from server identity, so re-importing a subscription keeps
measured latency and favourites.

**Interface**

- Home, Nodes, Rules, Logs, Settings; bottom navigation on mobile, a rail on
  desktop-sized windows
- Dark and light themes, following the system setting or pinned manually
- English and Chinese, following the system locale or pinned manually
- Latency measured through the tunnel when it is up — the engine URL-tests each
  proxy — and by bounded TCP handshakes for TCP nodes when it is not; UDP/QUIC
  nodes are measured after the tunnel starts so they are not falsely marked
  unreachable
- Nodes grouped by source, foldable, searchable, and sortable by latency
- Exit-IP readout, fetched through the tunnel, which is the one check that says
  whether traffic is really leaving by the node rather than the user's own line
- Subscriptions refresh themselves on connect when they have gone stale
- Generated-config inspector for diagnostics

**Routing rules**

- Bundled rule-sets answer the general case: China direct, ads blocked,
  everything else proxied
- Your own rules cover the specific one — one matcher, one destination each.
  Match on domain, domain-and-subdomains, domain substring, IP/CIDR, port, or
  process name; send to proxy, direct, or block
- Matched in the order shown, above the bundled lists, so a rule you typed for
  one domain beats a list of millions
- Reorderable, individually switchable off without being deleted, and validated
  before they reach the engine — a mistyped port is reported in the UI instead of
  becoming a tunnel that will not start
- Editing one reloads a running tunnel, so a rule applies immediately

## Requirements

```text
Flutter 3.47+
Dart 3.3+
```

For Android builds: JDK 17, Android SDK with NDK, and Go 1.24+ to build
`libbox.aar`.

For Linux builds, the tray needs appindicator headers on top of Flutter's usual
desktop toolchain — `tray_manager`'s CMake stops with a fatal error when it
cannot find them, so the bundle does not build without it:

```bash
sudo apt-get install libayatana-appindicator3-dev   # Debian, Ubuntu
sudo pacman -S --needed libayatana-appindicator     # Arch
```

## Build

`android/app/libs/libbox.aar` is not in the repository — it is a 23 MB binary
built from sing-box source. Build it first:

```bash
./scripts/build-libbox.sh
```

The script pins sing-box to a release tag, uses sing-box's own gomobile fork and
build-tag set, and writes the aar to `android/app/libs/`. It needs `ANDROID_HOME`
and `ANDROID_NDK_HOME` set, or a standard SDK location it can discover.

Then:

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

`--target-platform android-arm64` matters: the aar is built for arm64 only, so a
universal APK would ship other ABIs without `libbox.so` and crash on launch.

Desktop builds need no aar:

```bash
flutter run -d linux
flutter run -d windows
```

On Windows, import a subscription and press **Connect**. System-proxy mode is the
default and automatically configures WinINet. For transparent TCP/UDP capture,
choose **Settings → Proxy mode → TUN**; the optional **System HTTP proxy** setting
also configures WinINet for applications that ignore the virtual adapter. Windows
will request UAC elevation on the first TUN start, and the new elevated instance
will continue the requested connection automatically.

### Packaging

`scripts/package.sh` builds the distributables in one pass, into `dist/`:

```bash
scripts/package.sh            # everything this host can manage
scripts/package.sh deb apk    # or a named subset
```

| Artifact | Needs |
| --- | --- |
| `singbox-client_<version>-<build>_amd64.deb` | nothing past the Linux toolchain above — `dpkg-deb` when present, otherwise `ar` + `tar` |
| `singbox-client-<version>-<build>-x86_64.pkg.tar.zst` | `makepkg` and `fakeroot`, so an Arch host |
| `singbox-client-<version>-<build>-arm64.apk` | a JDK, an Android SDK, and `android/app/libs/libbox.aar` |
| `singbox-client-windows-x64-<sha>.zip` | a Windows runner with Visual Studio's C++ toolchain and the pinned sing-box archive |

Whatever is missing a tool is skipped with the reason printed; the rest still
build. Icons are rasterized from `docs/design/icon/ic_launcher.svg` with
`rsvg-convert`, falling back to the xxxhdpi launcher PNG.

Both Linux packages install the same layout: the bundle under
`/usr/lib/singbox-client/`, reached through a `/usr/bin/singbox-client` symlink,
plus a desktop entry and hicolor icons. Neither needs root to build — the deb
falls back to `ar`+`tar`, and `makepkg` refuses to run as root anyway. Both
declare the appindicator runtime libraries as hard dependencies, because the
binary links them and will not load without them.

## Continuous integration

`.github/workflows/build.yml` runs five jobs:

| Job | Runner | Produces |
| --- | --- | --- |
| `verify` | `ubuntu-latest` | `flutter analyze`, `flutter test` |
| `package` | `ubuntu-latest` | the deb and the arm64 APK |
| `windows` | `windows-latest` | the Windows x64 release bundle (`.zip`) |
| `arch` | `archlinux:base-devel` container | the `.pkg.tar.zst` |
| `release` | `ubuntu-latest` | on a `v*` tag, one GitHub Release with whatever built |

`ubuntu-latest` supplies the JDK 17, Android SDK, and NDK that
`scripts/build-libbox.sh` needs and a typical desktop checkout does not.
`libbox.aar` is cached on `SINGBOX_TAG`, so only the first run pays the ~15
minutes to build it. Both Linux jobs install the appindicator package their
distribution names, since the tray is a build dependency rather than a runtime
one.

The Arch package gets its own job because `makepkg` — which is what writes
`.PKGINFO`, `.MTREE` and `.BUILDINFO` — exists only on Arch, and because a deb
built there would link a glibc newer than Debian ships. Inside the container
everything runs as an unprivileged user: neither `makepkg` nor `flutter` will
run as root.

Every build job uploads its own artifacts, and `release` runs even when one of
them failed, so a broken artifact does not withhold the others.

One thing the workflow deliberately leaves alone: **signing** stays on the debug
key, as `android/app/build.gradle.kts` already does. The APK is for testing.

## Verification

```bash
flutter analyze
flutter test
```

468 tests pass: share-link parsing, config rendering, custom-rule validation and
placement, import format detection, the Clash API client both desktop runtimes
drive, the polkit capability grant, the Linux system-proxy backend against fakes,
the shutdown path, the single-instance socket, tray menu construction, UI
interaction against a fake controller, and localization/theme coverage including
palette contrast ratios. Windows privilege decisions have unit coverage; its
WinINet bridge, Job Object, and live TUN adapter still need a Windows session.

Visual regression snapshots are gated behind an environment variable, because
they render on the host's font stack and are only meaningful where they were
recorded:

```bash
VISUAL_SNAPSHOTS=1 flutter test test/visual_snapshot_test.dart
```

End-to-end tunnel behaviour — a real node carrying real traffic — has not been
verified in an automated way and needs a real subscription to exercise. The same
holds for anything that depends on what the engine reports at runtime, including
the URL-test delays behind latency sorting.

Three desktop paths are covered by unit tests but have not been exercised on a
live desktop session: the tray icon appearing on a panel and its menu opening,
the polkit/UAC prompt a first TUN start puts up, and the window hide/show cycle.
Their logic is tested against fakes — menu contents, quit ordering, `pkexec`
argv, socket handoff — which is not the same as having watched them happen.

## Localization

Strings live in `lib/l10n/app_en.arb` and `app_zh.arb`. After editing:

```bash
flutter gen-l10n
```

`AppState` never builds user-facing sentences; it reports a `NoticeKind` that the
UI translates, so business logic stays free of `BuildContext`.

## Platform status

| Platform | Proxy runtime | UI |
| --- | --- | --- |
| Android (arm64) | sing-box via libbox + VpnService | yes |
| Linux (x86_64) | supervised `sing-box` process + Clash API | yes |
| Windows (x64) | supervised `sing-box.exe` + WinINet system proxy or elevated Wintun TUN | yes |

Both desktop runtimes are the same supervised-process adapter over the Clash API,
described in [`docs/architecture.md`](docs/architecture.md); they differ in how
the system proxy is set — `gsettings`/`kwriteconfig` on Linux, WinINet on Windows
— and in their privilege flow. Linux grants file capabilities to its installed
core; Windows relaunches the app through UAC when TUN is selected.

Linux needs `sing-box` 1.12 or newer on `PATH` — the rendered config uses 1.12
schema. `SINGBOX_BINARY` overrides the lookup. Which mode to run:

| Mode | Privileges | Catches |
| --- | --- | --- |
| System proxy | none | applications that honour the desktop proxy settings; TCP only |
| TUN | `CAP_NET_ADMIN` | everything, UDP included |

**System proxy is the default**, so a fresh install connects without asking for
anything. Switching to TUN costs one authorization: before starting the engine the
app checks the binary's file capabilities and, if they are missing, asks for them
through polkit — the same password dialog the desktop uses for mounting a disk —
by running

```bash
pkexec setcap cap_net_admin,cap_net_raw+ep /usr/bin/sing-box
```

The capability lives on the binary, and the app spawns `sing-box` as its own
child, so this is asked once rather than per connection: no privileged helper is
installed and nothing elevates the app itself. A `sing-box` package upgrade
replaces the file and the prompt comes back on the next TUN start.

Only a `sing-box` under a system prefix (`/usr`, `/opt`, `/bin`, `/sbin`) is
elevated this way, because the path can come from `SINGBOX_BINARY` and running
`setcap` as root against an arbitrary path would grant capabilities to a file of
the caller's choosing. A binary elsewhere still runs — grant it by hand:

```bash
sudo setcap cap_net_admin,cap_net_raw+ep /path/to/sing-box
```

If the prompt is dismissed, or the system has no polkit agent, TUN mode reports
that with the manual command; system-proxy mode works untouched. See
[`docs/architecture.md`](docs/architecture.md) for how the runtimes divide up
the same `ProxyController` interface.

## Known gaps

- Release builds are signed with the debug key
  (`android/app/build.gradle.kts`). Replace before distributing.
- arm64 only. Other ABIs need another `scripts/build-libbox.sh` run with a
  different `-target`.
- Per-app proxy is modelled in settings but has no UI yet.
- Both Linux packages are verified structurally — deb member order and control
  fields, `pacman -Qip` metadata, root ownership, the `/usr/bin` symlink, the
  desktop entry — but neither has been installed on a live system.
- The Linux runtime is covered by unit tests against fakes, not by a live tunnel:
  no automated test starts a real `sing-box`, creates a tun, or writes real
  desktop proxy settings.
- The Windows runtime is covered by static and unit checks, not a live UAC/TUN
  session; a Windows machine is still needed to verify adapter creation and
  route rollback end to end.
- Linux has no privileged helper. TUN depends on a file capability on the
  `sing-box` binary, granted through polkit and cleared by a package upgrade,
  which brings the prompt back. A systemd or polkit-installed helper would
  survive that.
- Only GNOME and KDE system-proxy backends are implemented. Elsewhere the mode
  starts the engine and says in the log page that it could not set the
  desktop's proxy.
- The tray needs something on the panel to host it. On GNOME that is an
  AppIndicator extension, which is not installed by default; without one the icon
  never appears, and the close button then quits instead of hiding.
- Tray tooltips and click events are Windows-only. Linux's AppIndicator hands the
  menu to the panel and reports no clicks, so the menu's first item is the way
  back to the window.
- The exit-IP readout asks a third-party echo service (`ip.sb`, `ifconfig.co`),
  which sees the tunnel's exit address. It runs on connect and on node switch;
  there is no setting to turn it off yet.
- Custom rules cover one matcher and one destination each. Anything needing two
  conditions at once is a config file, which this app renders but does not accept
  hand edits to.

## Security

Node credentials, subscription tokens, UUIDs, and passwords live in local
storage and in the rendered config. They are redacted from logs and error
messages, but the generated-config viewer shows them in full by design — it
warns before displaying.

Never commit subscription URLs containing tokens, keystores, or generated
runtime state.

## License

GPL-3.0-or-later — see [`LICENSE`](LICENSE). Copyright 2026 WildAlley.

The choice is not free: the Android build links `libbox.aar`, compiled from
[sing-box](https://github.com/SagerNet/sing-box) source, which is GPLv3 *or
later*. The distributed APK is a combined work, so its terms have to be
compatible. Two consequences worth knowing before publishing a binary:

- Anyone who receives the APK is entitled to the corresponding source. The
  repository is public, which is what meets that obligation.
- sing-box adds a clause of its own: no derivative work may use its name or
  imply association with it without prior consent.

The Linux packages contain no sing-box code: the runtime there executes a
`sing-box` the user installed separately, so nothing of it is copied or linked
in. They share this repository, so they carry the same license anyway. The deb
declares it in `usr/share/doc/singbox-client/copyright`, the Arch package in
`usr/share/licenses/singbox-client/LICENSE`.
