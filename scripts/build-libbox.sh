#!/usr/bin/env bash
# Builds android/app/libs/libbox.aar, the sing-box core this app links against.
#
# The .aar is ~22 MB (62 MB of Go inside), so it is not committed. Run this once
# per checkout, or whenever SINGBOX_TAG changes.
#
# Requirements: Go 1.24+, JDK 17, Android SDK with NDK, git.
# Point JAVA_HOME / ANDROID_HOME at your own installs, or let the script probe
# the usual locations.
#
# Usage:
#   scripts/build-libbox.sh                 # android/arm64 (default)
#   ABIS=android scripts/build-libbox.sh    # all ABIs (much slower, ~4x size)
#   SINGBOX_TAG=v1.13.19 scripts/build-libbox.sh
set -euo pipefail

SINGBOX_TAG="${SINGBOX_TAG:-v1.13.19}"
# sing-box pins its own gomobile fork; the upstream one produces different
# bindings and will not compile against experimental/libbox.
GOMOBILE_VERSION="${GOMOBILE_VERSION:-v0.1.12}"
ABIS="${ABIS:-android/arm64}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${TMPDIR:-/tmp}/singbox-libbox-build}"
OUT="$REPO_ROOT/android/app/libs/libbox.aar"

die() { echo "error: $*" >&2; exit 1; }

# ---------------------------------------------------------------- toolchain

command -v go >/dev/null || die "go not found in PATH"
command -v git >/dev/null || die "git not found in PATH"

# JDK 17 exactly: sing-box's own build script rejects anything else, because
# gomobile's generated Java targets that release.
if [[ -z "${JAVA_HOME:-}" ]]; then
  for candidate in \
    /usr/lib/jvm/java-17-openjdk /usr/lib/jvm/java-17-openjdk-amd64 \
    /usr/lib/jvm/temurin-17-jdk /opt/homebrew/opt/openjdk@17 \
    "${TMPDIR:-/tmp}/android-build/jdk"
  do
    [[ -x "$candidate/bin/java" ]] && { export JAVA_HOME="$candidate"; break; }
  done
fi
[[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]] \
  || die "JDK 17 not found; set JAVA_HOME"
"$JAVA_HOME/bin/java" --version 2>&1 | grep -q "openjdk 17" \
  || die "JAVA_HOME must be a JDK 17 install (found: $("$JAVA_HOME/bin/java" --version 2>&1 | head -1))"

if [[ -z "${ANDROID_HOME:-}" ]]; then
  for candidate in \
    "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" \
    "${TMPDIR:-/tmp}/android-build/sdk"
  do
    [[ -n "$candidate" && -d "$candidate/platform-tools" ]] \
      && { export ANDROID_HOME="$candidate"; break; }
  done
fi
[[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]] \
  || die "Android SDK not found; set ANDROID_HOME"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  # Highest installed NDK.
  ANDROID_NDK_HOME="$(find "$ANDROID_HOME/ndk" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
    | sort -V | tail -1)"
fi
[[ -n "$ANDROID_NDK_HOME" && -d "$ANDROID_NDK_HOME" ]] \
  || die "Android NDK not found; set ANDROID_NDK_HOME"
export ANDROID_NDK_HOME

# Go 1.27 turns on the jsonv2 experiment by default. That breaks
# go-json-experiment/json's alias layer with "undefined: json.SkipFunc", and
# gomobile swallows the compiler output, so the failure looks like an opaque
# "exit status 1". Disabling the experiment is the fix.
export GOEXPERIMENT="${GOEXPERIMENT:-nojsonv2}"

GOBIN="$(go env GOPATH)/bin"
export PATH="$JAVA_HOME/bin:$GOBIN:$PATH"

echo "JAVA_HOME=$JAVA_HOME"
echo "ANDROID_HOME=$ANDROID_HOME"
echo "ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
echo "GOEXPERIMENT=$GOEXPERIMENT"
echo "sing-box=$SINGBOX_TAG  abis=$ABIS"

# ------------------------------------------------------------------ sources

mkdir -p "$WORK_DIR"
SRC="$WORK_DIR/sing-box"
if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" fetch --tags --depth 1 origin "$SINGBOX_TAG"
  git -C "$SRC" checkout -q FETCH_HEAD
else
  git clone --depth 1 --branch "$SINGBOX_TAG" \
    https://github.com/SagerNet/sing-box "$SRC"
fi

echo "installing gomobile $GOMOBILE_VERSION (sing-box fork)"
go install "github.com/sagernet/gomobile/cmd/gomobile@$GOMOBILE_VERSION"
go install "github.com/sagernet/gomobile/cmd/gobind@$GOMOBILE_VERSION"

# --------------------------------------------------------------------- build

# Build tags from sing-box's cmd/internal/build_libbox, minus
# with_naive_outbound.
#
# That tag pulls in sagernet/cronet-go, whose cgo layer needs a prebuilt Cronet
# static library that the Go module does not vendor — its lib/ directory ships
# empty, so `#include <cronet_c.h>` resolves but every symbol comes back
# undefined and cgo fails with "did not produce error". Upstream builds a second
# "legacy" variant with exactly this tag filtered out, so dropping it is their
# own supported configuration, not a hack.
#
# The cost is the naive outbound protocol, which this app cannot express:
# NodeProtocol (lib/models/node.dart) has no naive member, and nothing in lib/
# references it. Add the tag back — and vendor Cronet — only if that changes.
TAGS="with_gvisor,with_quic,with_wireguard,with_utls"
TAGS="$TAGS,with_clash_api,badlinkname,tfogo_checklinkname0,with_tailscale"
TAGS="$TAGS,ts_omit_logtail,ts_omit_ssh,ts_omit_drive,ts_omit_taildrop"
TAGS="$TAGS,ts_omit_webclient,ts_omit_doctor,ts_omit_capture,ts_omit_kube"
TAGS="$TAGS,ts_omit_aws,ts_omit_synology,ts_omit_bird"

LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=$SINGBOX_TAG"
LDFLAGS="$LDFLAGS -X internal/godebug.defaultGODEBUG=multipathtcp=0"
LDFLAGS="$LDFLAGS -s -w -buildid= -checklinkname=0"

mkdir -p "$(dirname "$OUT")"
cd "$SRC"

echo "building libbox.aar — this takes several minutes"
gomobile bind -v \
  -o "$OUT" \
  -target "$ABIS" \
  -androidapi 23 \
  -javapkg=io.nekohasekai \
  -libname=box \
  -trimpath \
  -buildvcs=false \
  -ldflags "$LDFLAGS" \
  -tags "$TAGS" \
  ./experimental/libbox

echo
echo "built $OUT"
ls -la "$OUT"

# Guard against the mistake that produces a crash-on-launch APK: an .aar with
# fewer ABIs than the app ships.
#
# app/build.gradle.kts pins abiFilters to arm64-v8a, but that only constrains
# what the NDK compiles — Flutter's own libapp.so and libflutter.so arrive as
# Maven artifacts and ignore it, so a plain `flutter build apk` still emits
# armeabi-v7a and x86_64 folders with no libbox.so in them. Build with
# `--target-platform android-arm64` (see README) to keep the APK to the one ABI
# this aar covers.
echo "ABIs in the .aar:"
unzip -l "$OUT" | grep -o 'jni/[^/]*' | sort -u
