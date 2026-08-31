#!/usr/bin/env bash
# Builds the distributable artifacts into dist/:
#
#   deb   — the bundle under /usr/lib, a symlink in /usr/bin
#   arch  — the same layout as a .pkg.tar.zst, assembled by makepkg
#   apk   — Android arm64, only when a JDK and an Android SDK are present
#
# Name targets to build a subset; with no arguments it builds all three:
#
#   scripts/package.sh            # whatever this host can manage
#   scripts/package.sh deb apk    # what a Debian-family CI runner can manage
#   scripts/package.sh arch       # what only an Arch host can
#
# Nothing here needs root: the deb is assembled with ar+tar when dpkg-deb is
# missing, and makepkg brings its own fakeroot — it refuses to run as root.
set -euo pipefail

cd "$(dirname "$0")/.."
root=$PWD

ALL_TARGETS='deb arch apk'
targets=${*:-$ALL_TARGETS}
for t in $targets; do
  case " $ALL_TARGETS " in
    *" $t "*) ;;
    *) echo "unknown target: $t (known: $ALL_TARGETS)" >&2; exit 2 ;;
  esac
done
wants() { case " $targets " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

APP_NAME="SingBox Client"
BINARY=singbox_client
APP_ID=com.wildalley.singbox_client
PKG=singbox-client
URL=https://github.com/wildalley/singbox-client

# pubspec carries "0.1.0+1": the left half is the release, the right the build.
raw_version=$(sed -n 's/^version: *//p' pubspec.yaml | head -1)
VERSION=${raw_version%%+*}
BUILD=${raw_version##*+}

out=$root/dist
work=$root/build/packaging
rm -rf "$work"
mkdir -p "$out" "$work"

say() { printf '\n== %s\n' "$1"; }

# --- Linux bundle -----------------------------------------------------------
# Both Linux packages ship the same bundle, so build it once, and only when one
# of them was asked for.

bundle=$root/build/linux/x64/release/bundle
icons=$work/icons

if wants deb || wants arch; then
  say "flutter build linux --release"
  flutter build linux --release
  [ -x "$bundle/$BINARY" ] || { echo "bundle missing: $bundle/$BINARY" >&2; exit 1; }

  # The launcher SVG is the only scalable source; Android's PNGs stop at 192px.
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
fi

# --- Shared install tree ----------------------------------------------------
# The whole Flutter bundle under /usr/lib, reached through a symlink in
# /usr/bin, plus a desktop entry and the hicolor icon sizes. The binary
# resolves lib/ and data/ relative to itself, which is why it stays put and
# only the symlink moves.

stage_tree() {
  local dest=$1 size dir
  install -d "$dest/usr/lib/$PKG" "$dest/usr/bin" "$dest/usr/share/applications"
  cp -r "$bundle/." "$dest/usr/lib/$PKG/"
  ln -sf "/usr/lib/$PKG/$BINARY" "$dest/usr/bin/$PKG"
  cat > "$dest/usr/share/applications/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=sing-box client
Exec=$PKG
Icon=$APP_ID
Categories=Network;
Terminal=false
StartupWMClass=$BINARY
DESKTOP
  for size in 64 128 256 512; do
    dir=$dest/usr/share/icons/hicolor/${size}x${size}/apps
    install -d "$dir"
    cp "$icons/$size.png" "$dir/$APP_ID.png"
  done
}

# --- deb --------------------------------------------------------------------

if wants deb; then
  say "deb"
  debroot=$work/deb
  stage_tree "$debroot"
  install -d "$debroot/DEBIAN"

  # Debian keeps the license under /usr/share/doc, in this machine-readable
  # format, and ships the GPLv3 text itself — so it is referenced, not copied.
  install -d "$debroot/usr/share/doc/$PKG"
  cat > "$debroot/usr/share/doc/$PKG/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $APP_NAME
Source: $URL

Files: *
Copyright: 2026 WildAlley
License: GPL-3.0-or-later
 This program is free software: you can redistribute it and/or modify it under
 the terms of the GNU General Public License as published by the Free Software
 Foundation, either version 3 of the License, or (at your option) any later
 version.
 .
 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 details.
 .
 On Debian systems the full text of the GNU General Public License version 3
 can be found in /usr/share/common-licenses/GPL-3.
COPYRIGHT

  # Installed-Size is what dpkg reports before unpacking; kibibytes.
  installed_size=$(du -ks "$debroot/usr" | cut -f1)
  cat > "$debroot/DEBIAN/control" <<CONTROL
Package: $PKG
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

  deb=$out/${PKG}_${VERSION}-${BUILD}_amd64.deb
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
fi

# --- Arch package -----------------------------------------------------------
# makepkg does the work: it writes .PKGINFO, .MTREE and .BUILDINFO, and packs
# with the zstd settings the host's makepkg.conf specifies. Hand-rolling the
# tarball would skip all three.

if wants arch; then
  say "pkg.tar.zst"
  arch_skip=
  command -v makepkg >/dev/null || arch_skip="makepkg not found — Arch hosts only"
  [ -n "$arch_skip" ] || command -v fakeroot >/dev/null || \
    arch_skip="fakeroot missing (pacman -S --needed base-devel)"
  [ -n "$arch_skip" ] || [ "$(id -u)" != 0 ] || \
    arch_skip="makepkg refuses to run as root; run this as your own user"

  if [ -n "$arch_skip" ]; then
    echo "  skipped: $arch_skip" >&2
  else
    archdir=$work/arch
    install -d "$archdir"
    stage_tree "$archdir/root"
    install -Dm644 "$root/LICENSE" \
      "$archdir/root/usr/share/licenses/$PKG/LICENSE"

    # depends: what the bundle actually links against, mapped to packages.
    # gtk3 pulls in the pango/cairo/gdk-pixbuf/atk/harfbuzz/glib/epoxy stack,
    # so listing it covers every NEEDED entry but the three below.
    # license: GPL-3.0-or-later, because the Android build links libbox built
    # from sing-box, which is GPLv3+. Arch's own copy lives in
    # /usr/share/licenses/common/GPL3, so only the verbatim text is installed.
    cat > "$archdir/PKGBUILD" <<PKGBUILD
pkgname=$PKG
pkgver=$VERSION
pkgrel=$BUILD
pkgdesc='sing-box client'
arch=('x86_64')
url='$URL'
license=('GPL-3.0-or-later')
depends=('gtk3' 'gcc-libs' 'glibc' 'zlib')
# !strip: the Flutter engine and libapp.so ship as they were built.
options=('!strip' '!debug')

package() {
  cp -a "\$startdir/root/." "\$pkgdir/"
}
PKGBUILD

    pkgfile=$out/${PKG}-${VERSION}-${BUILD}-x86_64.pkg.tar.zst
    rm -f "$pkgfile"
    # -d: nothing is compiled here, so the depends list is metadata only and
    # need not be installed to produce the package.
    if ( cd "$archdir" && PKGDEST=$out BUILDDIR=$archdir/build \
           PKGEXT=.pkg.tar.zst makepkg -f -d ) >"$work/makepkg.log" 2>&1; then
      echo "  $pkgfile"
    else
      echo "  failed, see $work/makepkg.log" >&2
      tail -5 "$work/makepkg.log" >&2
    fi
  fi
fi

# --- APK --------------------------------------------------------------------
# Needs a JDK and an Android SDK, neither of which the Linux build requires.
# libbox.aar is not in the repository — scripts/build-libbox.sh makes it.

if wants apk; then
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
    apk=$out/${PKG}-${VERSION}-${BUILD}-arm64.apk
    cp "$built" "$apk"
    echo "  $apk"
  fi
fi

# --- Summary ----------------------------------------------------------------

say "dist/"
ls -lh "$out"
