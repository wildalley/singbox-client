#!/usr/bin/env bash
# Rasterizes docs/design/icon/*.svg into the pre-26 launcher PNGs.
#
# API 26+ gets the vector adaptive icon (res/drawable/ic_launcher_*.xml), so
# these only serve Android 7.x — but minSdk is 24, so they ship. The _round set
# is narrower still: API 25 is the only level that asks for it.
#
# Needs rsvg-convert (librsvg). Re-run after editing an SVG and commit the
# PNGs; the build does not generate them.
set -euo pipefail

cd "$(dirname "$0")/.."
res=android/app/src/main/res

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert not found (Arch: pacman -S librsvg)" >&2
  exit 1
}

# Android's launcher-icon densities: mdpi is 48px, each step scales from there.
for name in ic_launcher ic_launcher_round; do
  for entry in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    density=${entry%%:*}
    size=${entry##*:}
    out=$res/mipmap-$density/$name.png
    mkdir -p "$(dirname "$out")"
    rsvg-convert -w "$size" -h "$size" -o "$out" "docs/design/icon/$name.svg"
    echo "$out  ${size}x${size}"
  done
done
