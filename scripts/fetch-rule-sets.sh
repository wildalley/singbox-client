#!/usr/bin/env bash
# Refreshes the routing rule-sets bundled in assets/rule-sets/.
#
# These ship inside the APK instead of being downloaded at start: sing-box
# initializes a `remote` rule-set *during* start and a failed fetch is fatal,
# with no per-rule-set optional flag — and the CN lists are wanted by exactly
# the users who cannot reach raw.githubusercontent.com. See lib/data/rule_sets
# .dart for the whole argument.
#
# So the lists are only as fresh as the last APK. Re-run this, then commit the
# .srs files; the build does not fetch them.
set -euo pipefail

cd "$(dirname "$0")/.."
out=assets/rule-sets
mkdir -p "$out"

# <asset name>:<repo>:<file in that repo's rule-set branch>. Asset names are the
# rule-set tags the config uses, which is not always the upstream file name —
# and geoip lives in a different repo from geosite, which is worth keeping
# visible: pointing geoip-cn at sing-geosite is a silent 404.
sets=(
  "geosite-cn:sing-geosite:geosite-geolocation-cn.srs"
  "geoip-cn:sing-geoip:geoip-cn.srs"
  "geosite-ads:sing-geosite:geosite-category-ads-all.srs"
)

for entry in "${sets[@]}"; do
  IFS=: read -r tag repo file <<<"$entry"
  url="https://raw.githubusercontent.com/SagerNet/$repo/rule-set/$file"
  tmp=$(mktemp)
  curl -fsSL --retry 3 -o "$tmp" "$url"
  # SRS binary header, so a captive portal's HTML login page cannot land here
  # and only fail later, on the device, as an unreadable rule-set.
  if [ "$(head -c 3 "$tmp")" != "SRS" ]; then
    echo "$url did not return an SRS file" >&2
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$out/$tag.srs"
  chmod 644 "$out/$tag.srs"
  echo "$out/$tag.srs  $(wc -c <"$out/$tag.srs") bytes  <- $repo/$file"
done
