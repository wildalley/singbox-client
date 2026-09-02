/// Synapse V4 design tokens, in dark and light variants.
///
/// Colours live in an [AppPalette] theme extension rather than in static
/// constants, so both brightnesses can share one widget tree. Read them with
/// `context.palette`.
///
/// Light mode is not a mechanical inversion: [AppPalette.violetSoft] and
/// [AppPalette.mint] are used as *foreground* colours, so on a white surface
/// they have to get darker, not lighter, to stay legible.
library;

import 'package:flutter/material.dart';

/// Semantic colour set for one brightness.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.faint,
    required this.violet,
    required this.violetSoft,
    required this.mint,
    required this.sky,
    required this.amber,
    required this.danger,
  });

  /// Page background, one step behind [surface].
  final Color bg;

  /// Default panel/card fill.
  final Color surface;

  /// Inset fill, e.g. inside a panel.
  final Color surface2;

  /// Raised fill: snackbars, chips, code blocks.
  final Color surface3;

  final Color border;
  final Color borderStrong;

  /// Primary body text.
  final Color text;

  /// Secondary text; meets 4.5:1 against [surface].
  final Color muted;

  /// Tertiary text and disabled glyphs.
  ///
  /// Also meets 4.5:1 against [surface]. It looks decorative, but it carries
  /// real content — log timestamps, node addresses, the punctuation in the
  /// config preview — so it is held to the same bar as [muted], just quieter.
  /// Against [surface3] it falls below that, which is why the only thing drawn
  /// on that fill is a disabled glyph.
  final Color faint;

  /// Brand fill for buttons and selected states.
  final Color violet;

  /// Brand *foreground*: icons and links on [surface].
  final Color violetSoft;

  /// Healthy / connected.
  final Color mint;

  /// Second data colour: charts, the downlink series, glow highlights.
  final Color sky;

  /// Warning.
  final Color amber;

  /// Error.
  final Color danger;

  static const dark = AppPalette(
    bg: Color(0xFF000E13),
    surface: Color(0xFF141B21),
    surface2: Color(0xFF1F2430),
    surface3: Color(0xFF2A3140),
    border: Color(0x1AFFFFFF),
    borderStrong: Color(0x2EFFFFFF),
    text: Color(0xFFE2E6F1),
    muted: Color(0xFF8A93A6),
    // Lifted from 6E7889, which was 3.90:1 on surface — fine for decoration,
    // short of the bar for the 10px text this actually draws. Taken past 4.5:1
    // on surface so it still clears it on a [tintFill] of itself, where the
    // fill lightens toward the text rather than away from it.
    faint: Color(0xFF828B9C),
    violet: Color(0xFF6C40FF),
    violetSoft: Color(0xFFB9A9FF),
    mint: Color(0xFF22E1A6),
    sky: Color(0xFF7FD2FF),
    amber: Color(0xFFF4B860),
    danger: Color(0xFFF07979),
  );

  static const light = AppPalette(
    bg: Color(0xFFF4F6F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF5F6F9),
    surface3: Color(0xFFE9EBEF),
    border: Color(0x14000000),
    borderStrong: Color(0x29000000),
    text: Color(0xFF0B1220),
    muted: Color(0xFF5C6779),
    // Darkened from 7C8698 (3.67:1 on white) for the reason above. Light mode
    // needs the bigger move: its surface is white, so there is no headroom.
    faint: Color(0xFF606B7C),
    violet: Color(0xFF5B34E8),
    // Darkened: this is a foreground colour on white.
    violetSoft: Color(0xFF4C28D6),
    // Darkened for the same reason; the dark-mode mint is 1.70:1 on white.
    // Darkened again past the on-white bar: the connection dial draws this
    // label on a disc filled with mint at 9%, and the old #0B7F58 measured
    // 4.42:1 there. Mint's only fills are the switch thumb and its 22% track,
    // which a deeper green does not hurt.
    mint: Color(0xFF0A7550),
    // Same story: dark sky is 1.67:1 on white, so light mode re-picks it.
    sky: Color(0xFF116E96),
    amber: Color(0xFF9A6300),
    danger: Color(0xFFC5323C),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? muted,
    Color? faint,
    Color? violet,
    Color? violetSoft,
    Color? mint,
    Color? sky,
    Color? amber,
    Color? danger,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      violet: violet ?? this.violet,
      violetSoft: violetSoft ?? this.violetSoft,
      mint: mint ?? this.mint,
      sky: sky ?? this.sky,
      amber: amber ?? this.amber,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      violetSoft: Color.lerp(violetSoft, other.violetSoft, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The palette for the current brightness.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

/// Font families. Inter and Space Grotesk are variable fonts (one file each);
/// JetBrains Mono ships Regular + Medium as separate files, which is the pair
/// [monoStyle] draws on.
///
/// None of the three ships CJK glyphs, so Chinese text has to come from a
/// system face. [cjkFallback] names those explicitly instead of relying on
/// implicit fallback, which differs per platform: Android resolves it via Noto
/// CJK, but a Linux or Windows desktop may not.
class AppFonts {
  const AppFonts._();

  static const body = 'Inter';
  static const display = 'SpaceGrotesk';
  static const mono = 'JetBrainsMono';

  /// Tried in order; unknown families are skipped by the engine.
  static const cjkFallback = <String>[
    'Noto Sans CJK SC', // Android, most Linux distros
    'Source Han Sans SC',
    'Microsoft YaHei', // Windows
    'PingFang SC', // macOS
    'Noto Sans SC',
    'sans-serif',
  ];
}

/// Spacing scale on an 8px grid, with 4 and 12 as half-steps.
class Gap {
  const Gap._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Section separation and hero whitespace.
  static const x3 = 48.0;
  static const x4 = 64.0;
  static const x5 = 96.0;
}

/// Corner radii, five steps. Prefixed rather than named `Radius`, which
/// `dart:ui` already takes.
class AppRadius {
  const AppRadius._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// Animation curve and durations.
///
/// One curve for everything: a strong ease-out, so motion arrives quickly and
/// settles instead of drifting.
class Motion {
  const Motion._();

  static const curve = Cubic(0.22, 1, 0.36, 1);

  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 500);
  static const slower = Duration(milliseconds: 800);
}

/// [duration], or zero when the platform asks for reduced motion.
///
/// Anything that moves on its own — a value tween, a reorder slide, a page
/// transition — reads its duration through here rather than from [Motion]
/// directly, so "reduce motion" is honoured in one place instead of per widget.
///
/// Implicit animations given a zero duration still land on the new value; they
/// just do it in one frame. So this removes the movement, not the update.
Duration motionOf(BuildContext context, Duration duration) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : duration;

/// Outer glow for emphasised elements: the connection dial, an active node, a
/// focused panel edge.
///
/// Two layers rather than one blur — a tight bright core plus a wide faint
/// halo. A single shadow big enough to read as a glow goes muddy instead.
///
/// [intensity] scales both alphas. Light theme wants roughly `0.35`: at full
/// strength a coloured glow on white reads as a smudge, not a light source.
List<BoxShadow> glow(Color c, {double intensity = 1}) => [
      BoxShadow(
        color: c.withValues(alpha: .28 * intensity),
        blurRadius: 24,
        spreadRadius: -4,
      ),
      BoxShadow(
        color: c.withValues(alpha: .12 * intensity),
        blurRadius: 48,
        spreadRadius: 2,
      ),
    ];

/// Glow strength for [brightness] — see [glow].
double glowIntensity(Brightness brightness) =>
    brightness == Brightness.dark ? 1 : 0.35;

/// Fill for a badge or tile tinted with the same colour as the text on it —
/// action badges, the node region tile, [StatusPill].
///
/// The alpha is low because of which way the tint moves contrast. Over the dark
/// surface it lightens the fill *away* from the text and contrast improves; over
/// white it pulls the fill *toward* the text and contrast drops. Light mode is
/// therefore the binding case, and one constant has to satisfy both: at .10 the
/// light mint badge falls to 4.37:1, under the bar for text this small. .07
/// holds every accent above 4.5:1 in both palettes — see the badge-fill
/// assertions in `test/localization_theme_test.dart`, which fail if this rises.
Color tintFill(Color c) => c.withValues(alpha: .07);

/// A style for a component theme — button labels, snackbar text, input hints,
/// navigation labels.
///
/// These sit outside [TextTheme] and so do not inherit the base family and CJK
/// fallback: a `textStyle` on `filledButtonTheme` replaces `labelLarge`
/// outright instead of merging into it, and the [Material] inside the button
/// installs it as a fresh [DefaultTextStyle] rather than merging with the
/// ambient one. Anything drawn from a component theme has to name the family
/// and the fallback chain itself, or Latin text loses Inter and Chinese text
/// falls back to whatever the platform picks.
TextStyle _componentStyle({
  double size = 13,
  FontWeight weight = FontWeight.w500,
  Color? color,
}) =>
    TextStyle(
      fontFamily: AppFonts.body,
      fontFamilyFallback: AppFonts.cjkFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
    );

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? AppPalette.dark : AppPalette.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.violet,
    onPrimary: Colors.white,
    secondary: palette.mint,
    onSecondary: dark ? const Color(0xFF06251A) : Colors.white,
    surface: palette.surface,
    onSurface: palette.text,
    error: palette.danger,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.bg,
    fontFamily: AppFonts.body,
    // Inter has no CJK glyphs, so Chinese text needs an explicit fallback.
    fontFamilyFallback: AppFonts.cjkFallback,
    splashFactory: InkSparkle.splashFactory,
    extensions: [palette],
    textTheme: TextTheme(
      // Display: Space Grotesk 700, tracking -0.03em (i.e. -0.03 × font size).
      headlineLarge: TextStyle(
        fontFamily: AppFonts.display,
        fontFamilyFallback: AppFonts.cjkFallback,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.84,
        color: palette.text,
      ),
      headlineMedium: TextStyle(
        fontFamily: AppFonts.display,
        fontFamilyFallback: AppFonts.cjkFallback,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.66,
        color: palette.text,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
      bodyMedium: TextStyle(fontSize: 13, height: 1.4, color: palette.text),
      bodySmall: TextStyle(fontSize: 11, color: palette.muted, height: 1.4),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: palette.muted,
      ),
    ),
    iconTheme: IconThemeData(color: palette.muted),
    dividerTheme: DividerThemeData(
      color: palette.border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surface3,
      contentTextStyle: _componentStyle(color: palette.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? palette.surface : palette.surface2,
      hintStyle: _componentStyle(color: palette.faint),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: palette.violet, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: _componentStyle(weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.violetSoft,
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: _componentStyle(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.violetSoft,
        textStyle: _componentStyle(),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.violet.withValues(alpha: .20),
      labelTextStyle: WidgetStatePropertyAll(
        _componentStyle(size: 11, color: palette.text),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? palette.violetSoft : palette.muted,
        );
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? palette.mint : null),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? palette.mint.withValues(alpha: dark ? .28 : .22)
              : palette.surface3),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.violetSoft,
    ),
  );
}

/// Monospace style for latency, speeds, ports, and addresses.
///
/// [color] is required because the right default differs per brightness.
///
/// No negative tracking here: the old `-0.2` was pulling in the platform
/// monospace face, which is wide. JetBrains Mono is already drawn tight, and
/// tightening it further breaks the column alignment this style exists for.
TextStyle monoStyle({
  required Color color,
  double size = 12,
  FontWeight weight = FontWeight.w500,
}) =>
    TextStyle(
      fontFamily: AppFonts.mono,
      // JetBrains Mono has no CJK glyphs either, and the config preview and
      // node rows can carry Chinese names.
      fontFamilyFallback: AppFonts.cjkFallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
    );

/// Colour for a latency reading: mint fast, amber usable, danger slow/failed.
Color latencyColor(AppPalette palette, int? latencyMs) {
  if (latencyMs == null) return palette.faint;
  if (latencyMs < 0) return palette.danger;
  if (latencyMs < 120) return palette.mint;
  if (latencyMs < 260) return palette.amber;
  return palette.danger;
}
