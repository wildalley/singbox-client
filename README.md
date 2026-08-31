# SingBox Client

A Flutter sing-box client for **Android**, with Windows and Linux sharing the same
UI and configuration layer. The interface follows the Google Stitch **Obsidian
Signal** design system, in dark and light variants, with English and Chinese
localization.

On Android the proxy actually runs: a Kotlin `VpnService` drives sing-box through
a self-built `libbox.aar`.

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
scripts/package.sh
```

| Artifact | Needs |
| --- | --- |
| `singbox-client_<version>_amd64.deb` | nothing past the Linux toolchain — `dpkg-deb` when present, otherwise `ar` + `tar` |
| `SingBox_Client-<version>-x86_64.AppImage` | `appimagetool` on `PATH`, or `APPIMAGETOOL=/path/to/it` |
| `singbox-client-<version>-<build>-arm64.apk` | a JDK, an Android SDK, and `android/app/libs/libbox.aar` |

Whatever is missing a tool is skipped with the reason printed; the rest still
build. Icons are rasterized from `docs/design/icon/ic_launcher.svg` with
`rsvg-convert`, falling back to the xxxhdpi launcher PNG.

## Continuous integration

`.github/workflows/build.yml` has two jobs: `flutter analyze` plus `flutter
test`, and the three artifacts above. It runs on `ubuntu-latest`, which supplies
the JDK 17, Android SDK, and NDK that `scripts/build-libbox.sh` needs and a
typical desktop checkout does not. `libbox.aar` is cached on `SINGBOX_TAG`, so
only the first run pays the ~15 minutes to build it.

Every run uploads the artifacts; a pushed `v*` tag also attaches them to a
GitHub Release.

Two things the workflow deliberately leaves to you:

- **appimagetool** has no apt package, and the workflow will not choose a
  download source on your behalf. Point the `APPIMAGETOOL_URL` repository
  variable at a build you trust — and `APPIMAGETOOL_SHA256` at its digest, which
  the run prints either way — and the AppImage is built. Left unset, that one
  artifact is skipped and the deb and APK still ship.
- **Signing** stays on the debug key, as `android/app/build.gradle.kts` already
  does. The APK is for testing.

## Verification

```bash
flutter analyze
flutter test
```

242 tests pass: share-link parsing, config rendering, import format detection,
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
| Linux | not implemented | yes |
| Windows | not implemented | yes |

Desktop platforms get `UnsupportedProxyController`: node management, import, and
config rendering all work, but starting a tunnel reports that the runtime is
missing. Supervised-process and TUN integration is the next step, per
[`docs/architecture.md`](docs/architecture.md).

## Known gaps

- Release builds are signed with the debug key
  (`android/app/build.gradle.kts`). Replace before distributing.
- arm64 only. Other ABIs need another `scripts/build-libbox.sh` run with a
  different `-target`.
- Per-app proxy is modelled in settings but has no UI yet.
- The deb is verified structurally — member order, control fields, root
  ownership, the `/usr/bin` symlink, the desktop entry — but has never been
  installed on a Debian or Ubuntu system.

## Security

Node credentials, subscription tokens, UUIDs, and passwords live in local
storage and in the rendered config. They are redacted from logs and error
messages, but the generated-config viewer shows them in full by design — it
warns before displaying.

Never commit subscription URLs containing tokens, keystores, or generated
runtime state.
