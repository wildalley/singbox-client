# SingBox Client

A Flutter sing-box client for **Android** and **Linux**, with Windows sharing the
same UI and configuration layer. The interface follows the Google Stitch
**Obsidian Signal** design system, in dark and light variants, with English and
Chinese localization.

Both platforms run the proxy, by different means. Android embeds the engine: a
Kotlin `VpnService` drives sing-box through a self-built `libbox.aar`. Linux
supervises an installed `sing-box` binary and drives it over its Clash API,
because `libbox.aar` is Android-only and a desktop tun needs a capability no
in-process library can grant itself.

## Features

**Proxy runtime (Android)**

- Foreground `VpnService` owning the VPN lifecycle, with a notification and a
  stop action
- sing-box v1.13 driven through `CommandServer` / `CommandClient`
- Live status, traffic counters, and log streaming into the UI
- Runtime node switching via the `selector` outbound, without restarting the
  tunnel
- `urltest` group as a selectable exit, so the engine can pick the fastest node
  itself
- The tunnel survives the Flutter engine being killed; reopening the app
  reattaches to the running service
- Routing rule-sets ship inside the APK, so a start needs no network; stale ones
  update themselves once the tunnel is up

**Proxy runtime (Linux)**

- Supervises an installed `sing-box` (≥ 1.12), driven over its Clash API: node
  switching, per-node URL tests, traffic, connection count, and memory
- Two modes. TUN captures everything but needs `CAP_NET_ADMIN`; system-proxy mode
  needs no privileges at all and points GNOME or KDE at the loopback inbound
- Restores the desktop's previous proxy settings on stop, and on next launch
  after an unclean exit
- Engine stdout/stderr streams into the log page, so a failed start is readable
  rather than silent
- Missing binary, too-old binary, and a tun the kernel refused are each reported
  with the fix, in the user's language

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
  proxy — and by TCP handshake with bounded concurrency when it is not
- Nodes grouped by source, foldable, searchable, and sortable by latency
- Subscriptions refresh themselves on connect when they have gone stale
- Generated-config inspector for diagnostics

## Requirements

```text
Flutter 3.47+
Dart 3.3+
```

For Android builds: JDK 17, Android SDK with NDK, and Go 1.24+ to build
`libbox.aar`.

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

### Packaging

`scripts/package.sh` builds the distributables in one pass, into `dist/`:

```bash
scripts/package.sh            # everything this host can manage
scripts/package.sh deb apk    # or a named subset
```

| Artifact | Needs |
| --- | --- |
| `singbox-client_<version>-<build>_amd64.deb` | nothing past the Linux toolchain — `dpkg-deb` when present, otherwise `ar` + `tar` |
| `singbox-client-<version>-<build>-x86_64.pkg.tar.zst` | `makepkg` and `fakeroot`, so an Arch host |
| `singbox-client-<version>-<build>-arm64.apk` | a JDK, an Android SDK, and `android/app/libs/libbox.aar` |

Whatever is missing a tool is skipped with the reason printed; the rest still
build. Icons are rasterized from `docs/design/icon/ic_launcher.svg` with
`rsvg-convert`, falling back to the xxxhdpi launcher PNG.

Both Linux packages install the same layout: the bundle under
`/usr/lib/singbox-client/`, reached through a `/usr/bin/singbox-client` symlink,
plus a desktop entry and hicolor icons. Neither needs root to build — the deb
falls back to `ar`+`tar`, and `makepkg` refuses to run as root anyway.

## Continuous integration

`.github/workflows/build.yml` runs four jobs:

| Job | Runner | Produces |
| --- | --- | --- |
| `verify` | `ubuntu-latest` | `flutter analyze`, `flutter test` |
| `package` | `ubuntu-latest` | the deb and the arm64 APK |
| `arch` | `archlinux:base-devel` container | the `.pkg.tar.zst` |
| `release` | `ubuntu-latest` | on a `v*` tag, one GitHub Release with whatever built |

`ubuntu-latest` supplies the JDK 17, Android SDK, and NDK that
`scripts/build-libbox.sh` needs and a typical desktop checkout does not.
`libbox.aar` is cached on `SINGBOX_TAG`, so only the first run pays the ~15
minutes to build it.

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

309 tests pass: share-link parsing, config rendering, import format detection,
the Linux runtime's Clash API client and desktop proxy backends against fakes,
UI interaction against a fake controller, and localization/theme coverage
including palette contrast ratios.

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
| Windows | not implemented | yes |

Windows gets `UnsupportedProxyController`: node management, import, and config
rendering all work, but starting a tunnel reports that the runtime is missing.

Linux needs `sing-box` 1.12 or newer on `PATH` — the rendered config uses 1.12
schema. `SINGBOX_BINARY` overrides the lookup. Which mode to run:

| Mode | Privileges | Catches |
| --- | --- | --- |
| System proxy | none | applications that honour the desktop proxy settings; TCP only |
| TUN | `CAP_NET_ADMIN` | everything, UDP included |

TUN is the default. The app cannot ask for the capability — there is no dialog
for it on Linux — so grant it once to the binary the app will run:

```bash
sudo setcap cap_net_admin,cap_net_raw+ep "$(command -v sing-box)"
```

File capabilities are lost when the `sing-box` package is upgraded, so that has
to be repeated. Without it, TUN mode reports the failure and the exact command;
system-proxy mode works untouched. See
[`docs/architecture.md`](docs/architecture.md) for how the two runtimes divide up
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
- Linux has no privileged helper. TUN depends on file capabilities on the
  `sing-box` binary, which a package upgrade clears; a systemd or polkit helper
  would survive that.
- Only GNOME and KDE system-proxy backends are implemented. Elsewhere the mode
  starts the engine and says in the log page that it could not set the
  desktop's proxy.

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
