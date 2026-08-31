#!/usr/bin/env bash
# Builds the distributable artifacts into dist/:
#
#   AppImage  — portable, relies on the host GTK3
#   deb       — installs the bundle under /usr/lib, symlink in /usr/bin
#   apk       — only when a JDK and Android SDK are present, see apk_skip_reason
#
# Everything lands in dist/. Nothing here needs root: the deb is assembled with
# ar+tar when dpkg-deb is missing, and appimagetool is only ever used from where
# it already is -- $APPIMAGETOOL, PATH, or ~/.cache/singbox-packaging.
set -euo pipefail

cd "$(dirname "$0")/.."
root=$PWD

APP_NAME="SingBox Client"
BINARY=singbox_client
APP_ID=com.wildalley.singbox_client
DEB_PKG=singbox-client

# pubspec carries "0.1.0+1": the left half is the release, the right the build.
raw_version=$(sed -n 's/^version: *//p' pubspec.yaml | head -1)
VERSION=${raw_version%%+*}
BUILD=${raw_version##*+}

out=$root/dist
work=$root/build/packaging
cache=${XDG_CACHE_HOME:-$HOME/.cache}/singbox-packaging
rm -rf "$work"
mkdir -p "$out" "$work" "$cache"

say() { printf '\n== %s\n' "$1"; }

# --- Linux bundle -----------------------------------------------------------

say "flutter build linux --release"
flutter build linux --release
bundle=$root/build/linux/x64/release/bundle
[ -x "$bundle/$BINARY" ] || { echo "bundle missing: $bundle/$BINARY" >&2; exit 1; }

# --- Icons ------------------------------------------------------------------
# The launcher SVG is the only scalable source; Android's PNGs stop at 192px.

icons=$work/icons
mkdir -p "$icons"
if command -v rsvg-convert >/dev/null; then
  for size in 64 128 256 512; do
    rsvg-convert -w $size -h $size \
      -o "$icons/$size.png" docs/design/icon/ic_launcher.svg
  done
else
  echo "rsvg-convert missing, falling back to the xxxhdpi launcher PNG" >&2
  for size in 64 128 256 512; do
    cp android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png "$icons/$size.png"
  done
fi

# --- Shared desktop entry ---------------------------------------------------

desktop_entry() {
  # $1: value for Exec
  cat <<DESKTOP
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=sing-box client
Exec=$1
Icon=$APP_ID
Categories=Network;
Terminal=false
StartupWMClass=$BINARY
DESKTOP
}

# --- deb --------------------------------------------------------------------

say "deb"
debroot=$work/deb
install -d "$debroot/DEBIAN" \
  "$debroot/usr/lib/$DEB_PKG" \
  "$debroot/usr/bin" \
  "$debroot/usr/share/applications"

cp -r "$bundle/." "$debroot/usr/lib/$DEB_PKG/"
ln -sf "/usr/lib/$DEB_PKG/$BINARY" "$debroot/usr/bin/$DEB_PKG"
desktop_entry "$DEB_PKG" > "$debroot/usr/share/applications/$APP_ID.desktop"

for size in 64 128 256 512; do
  dir=$debroot/usr/share/icons/hicolor/${size}x${size}/apps
  install -d "$dir"
  cp "$icons/$size.png" "$dir/$APP_ID.png"
done

# Installed-Size is what dpkg reports before unpacking; kibibytes.
installed_size=$(du -ks "$debroot/usr" | cut -f1)
cat > "$debroot/DEBIAN/control" <<CONTROL
Package: $DEB_PKG
Version: $VERSION-$BUILD
Section: net
Priority: optional
Architecture: amd64
Depends: libc6, libstdc++6, libgtk-3-0, libglib2.0-0
Installed-Size: $installed_size
Maintainer: WildAlley <noreply@wildalley.invalid>
Description: sing-box client
 A Flutter sing-box client. This desktop build ships the interface,
 import, and config rendering; the proxy runtime is Android-only for now,
 so starting a tunnel reports that the runtime is missing.
CONTROL

deb=$out/${DEB_PKG}_${VERSION}-${BUILD}_amd64.deb
rm -f "$deb"
if command -v dpkg-deb >/dev/null; then
  dpkg-deb --root-owner-group --build "$debroot" "$deb" >/dev/null
else
  # No dpkg on Arch: a deb is just an ar archive of three members, in order.
  # --owner/--group keep the payload root-owned without needing fakeroot.
  ( cd "$debroot"
    echo '2.0' > "$work/debian-binary"
    tar czf "$work/control.tar.gz" --owner=root --group=root -C DEBIAN .
    tar czf "$work/data.tar.gz" --owner=root --group=root \
      --exclude=./DEBIAN -C . .
    ar rc "$deb" "$work/debian-binary" "$work/control.tar.gz" "$work/data.tar.gz" )
fi
echo "  $deb"

# --- AppImage ---------------------------------------------------------------

say "AppImage"
# appimagetool is never fetched here: that would mean downloading a binary and
# executing it. Install it yourself (AUR: appimagetool-bin) or point
# APPIMAGETOOL at a copy you trust.
appimagetool=${APPIMAGETOOL:-$(command -v appimagetool 2>/dev/null || true)}
if [ -z "$appimagetool" ] && [ -x "$cache/appimagetool" ]; then
  appimagetool=$cache/appimagetool
fi

if [ -z "$appimagetool" ] || [ ! -x "$appimagetool" ]; then
  echo "  skipped: appimagetool not found." >&2
  echo "           Install it (AUR: appimagetool-bin), or set" >&2
  echo "           APPIMAGETOOL=/path/to/appimagetool, then re-run." >&2
else
  appdir=$work/AppDir
  install -d "$appdir/usr/lib/$DEB_PKG" "$appdir/usr/bin" \
    "$appdir/usr/share/applications"
  cp -r "$bundle/." "$appdir/usr/lib/$DEB_PKG/"

  # AppRun, not a symlink: the binary finds its lib/ and data/ through $ORIGIN,
  # so it has to be launched from where it actually sits.
  cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
exec "$here/usr/lib/singbox-client/singbox_client" "$@"
APPRUN
  chmod +x "$appdir/AppRun"

  # appimagetool wants the desktop file and icon at the AppDir root too.
  desktop_entry "AppRun" > "$appdir/$APP_ID.desktop"
  cp "$appdir/$APP_ID.desktop" "$appdir/usr/share/applications/"
  cp "$icons/256.png" "$appdir/$APP_ID.png"
  for size in 64 128 256 512; do
    dir=$appdir/usr/share/icons/hicolor/${size}x${size}/apps
    install -d "$dir"
    cp "$icons/$size.png" "$dir/$APP_ID.png"
  done

  appimage=$out/${APP_NAME// /_}-${VERSION}-x86_64.AppImage
  rm -f "$appimage"
  # extract-and-run avoids needing FUSE inside the tool itself.
  if ARCH=x86_64 "$appimagetool" --appimage-extract-and-run \
       "$appdir" "$appimage" >"$work/appimagetool.log" 2>&1; then
    echo "  $appimage"
  else
    echo "  failed, see $work/appimagetool.log" >&2
    tail -5 "$work/appimagetool.log" >&2
  fi
fi

# --- APK --------------------------------------------------------------------
# Needs a JDK and an Android SDK, neither of which the Linux build requires.
# libbox.aar is not in the repository — scripts/build-libbox.sh makes it.

say "APK"
apk_skip=
command -v java >/dev/null || apk_skip="no JDK on PATH (Arch: pacman -S jdk17-openjdk)"
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
[ -n "$apk_skip" ] || [ -d "$sdk" ] || \
  apk_skip="no Android SDK at $sdk (set ANDROID_HOME)"
[ -n "$apk_skip" ] || [ -f android/app/libs/libbox.aar ] || \
  apk_skip="android/app/libs/libbox.aar missing, run scripts/build-libbox.sh"

if [ -n "$apk_skip" ]; then
  echo "  skipped: $apk_skip" >&2
else
  # arm64 only: the aar carries no other ABI, and a universal APK would ship
  # architectures without libbox.so and crash on launch.
  flutter build apk --release --target-platform android-arm64
  built=build/app/outputs/flutter-apk/app-release.apk
  apk=$out/${DEB_PKG}-${VERSION}-${BUILD}-arm64.apk
  cp "$built" "$apk"
  echo "  $apk"
fi

# --- Summary ----------------------------------------------------------------

say "dist/"
ls -lh "$out"
