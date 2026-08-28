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
- The tunnel survives the Flutter engine being killed; reopening the app
  reattaches to the running service

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
- TCP latency probing with bounded concurrency
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

## Verification

```bash
flutter analyze
flutter test
```

73 tests pass: share-link parsing, config rendering, import format detection,
UI interaction against a fake controller, and localization/theme coverage
including palette contrast ratios.

End-to-end tunnel behaviour — a real node carrying real traffic — has not been
verified in an automated way and needs a real subscription to exercise.

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

## Security

Node credentials, subscription tokens, UUIDs, and passwords live in local
storage and in the rendered config. They are redacted from logs and error
messages, but the generated-config viewer shows them in full by design — it
warns before displaying.

Never commit subscription URLs containing tokens, keystores, or generated
runtime state.
