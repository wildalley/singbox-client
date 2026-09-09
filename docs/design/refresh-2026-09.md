# Synapse visual refresh · 0.1.5

## Direction

The supplied Synapse V4 sheet is a visual reference, not a specification for
inventing new proxy features. Preserve SingBox's navigation and working controls.
The signature is a polished silver/violet ribbon S, repeated as restrained signal
artwork on the desktop rail and dashboard connection panel.

- Obsidian background `#080C12`, layered panels `#11171F` / `#1B222E`.
- Violet `#6C40FF` for emphasis; existing contrast-safe foreground accents and
  mint connection status remain. Light mode maps signal luminance to translucent
  violet, rather than showing a black rectangle under its controls.
- Space Grotesk headings, Inter UI, JetBrains Mono measurements; retain CJK
  fallback. Large desktop page titles and a baseline-aligned live-rate readout.
- Quiet 48px grid, restrained borders, subtle light-mode shadows. Node rows
  reserve purple borders for selection. Subscription folding behavior is intact.
- The raster art is used as the fibre base, while `SignalArtwork` adds a
  restrained throughput-driven drift and feathered highlight at runtime. It is
  excluded from semantics and cannot intercept pointer events; reduced-motion
  preferences keep it still.
- The mobile dial stays thumb-friendly. Shared panels, typography, palette and
  native icons carry the refresh to smaller screens without shrinking the
  desktop layout into them.

## Artwork and generation

Generated with the built-in image generation tool (not the fallback CLI).
No credentials, subscription content, or app screenshots containing user data
were sent as generation input. The supplied sheet informed the visual direction;
the icon and signal flow are new assets, not cropped pieces of the reference.

Saved assets:

- `docs/design/icon/app-icon-master.png`: original transparent 1280px master.
- `assets/branding/app-icon.png`: 256px runtime icon.
- `assets/branding/signal-flow.webp`: compressed runtime signal artwork.
- Native launchers: Android density PNGs and adaptive artwork, Windows ICO,
  and Linux hicolor PNGs generated during packaging.
- Native monochrome and tray marks are hand-authored, small-size S vectors;
  the tray uses a filled mint / hollow neutral status dot for shape + color cues.

Final prompt specifications used for the two generated assets:

**Icon — logo/brand, production asset.** SingBox proxy and traffic-management
application icon; a single bold S monogram made from a sculptural folded ribbon.
Polished silver top facets, electric violet `#6C40FF` inner faces, a tiny icy-cyan
edge glint; obsidian `#080D14` rounded-square tile. Center the mark within the
middle 62% for adaptive-mask safety. Clear silhouette at small sizes, controlled
studio lighting, deep dimensional folds, restrained glow. Transparent outside
the tile. Square 1024px requested. No letters beyond the S symbol, no text,
watermark, scene, decorative particles, duplicate tiles, or UI mockup.

**Signal flow — stylized concept, dashboard background asset.** Panoramic 2.5:1
obsidian `#080D14` field. One flowing silver/lavender glass ribbon with electric
violet `#6C40FF` light tracing its folds, sparse fine network filaments and nodes.
Sculptural depth and elegant S-like movement, occupying the right two-thirds and
lower half; generous dark upper-left negative space for real interface content.
Fade the edges softly into near-black. No text, numbers, controls, charts,
logos, watermark, or fake dashboard data.

## Regeneration and review

`scripts/build-icons.sh` mechanically resizes the generated master, builds the
Windows multi-resolution ICO and rasterizes small-size vectors. Requires librsvg
and ImageMagick. Do not recreate the raster source with these tools.

```
scripts/build-icons.sh
flutter analyze
flutter test
VISUAL_SNAPSHOTS=1 flutter test --update-goldens test/visual_snapshot_test.dart
scripts/package.sh arch
```

The snapshot harness waits for artwork decoding, loads real CJK fonts, and covers
both desktop themes in Chinese, the folded node list at 1270×720, mobile pages,
and the lower dashboard/settings content. Snapshot measurements are synthetic
test fixtures; the shipped dashboard uses actual engine samples only.

Linux native Release QA also exercised the Impeller renderer with isolated
in-memory preferences: both themes render the assets; a 46-node subscription
with four repeated-ID pairs expanded and collapsed three times with zero
remaining node render objects after every collapse. A native-only visual issue
found during this pass — shadows showing through the translucent disconnect
button on hover — was removed and covered by hover regression tests. A rate
readout test also prevents a tweened KB value from appearing beside an MB label.

Review decisions: keep art behind a readability scrim; avoid oversized reference
sheet slogans in working lists; keep neutral rows quiet so selection is clear;
preserve functional geometry and readable light mode. All essential controls
remain native widgets and data charts remain code-rendered.
