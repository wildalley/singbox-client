/// Obsidian Signal design tokens, in dark and light variants.
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
  final Color faint;

  /// Brand fill for buttons and selected states.
  final Color violet;

  /// Brand *foreground*: icons and links on [surface].
  final Color violetSoft;

  /// Healthy / connected.
  final Color mint;

  /// Warning.
  final Color amber;

  /// Error.
  final Color danger;

  static const dark = AppPalette(
    bg: Color(0xFF0D0D0D),
    surface: Color(0xFF171717),
    surface2: Color(0xFF1E1E1E),
    surface3: Color(0xFF262626),
    border: Color(0x1AFFFFFF),
    borderStrong: Color(0x2EFFFFFF),
    text: Color(0xFFF4F4F5),
    muted: Color(0xFF92929A),
    faint: Color(0xFF6B6B73),
    violet: Color(0xFF7C5CFC),
    violetSoft: Color(0xFFB9A9FF),
    mint: Color(0xFF4DDFAB),
    amber: Color(0xFFF4B860),
    danger: Color(0xFFF07979),
  );

  static const light = AppPalette(
    bg: Color(0xFFF4F4F6),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F7F9),
    surface3: Color(0xFFECECEF),
    border: Color(0x14000000),
    borderStrong: Color(0x29000000),
    text: Color(0xFF18181B),
    muted: Color(0xFF5C5C66),
    faint: Color(0xFF8A8A94),
    violet: Color(0xFF6242E0),
    // Darkened: this is a foreground colour on white.
    violetSoft: Color(0xFF5334CE),
    // Darkened for the same reason; the dark-mode mint fails contrast on white.
    mint: Color(0xFF0E8F62),
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

/// Font families. Both bundled faces are variable fonts; `mono` uses the
/// platform monospace face, which is what the design calls for on metrics.
///
/// Neither Inter nor Space Grotesk ships CJK glyphs, so Chinese text has to
/// come from a system face. [cjkFallback] names those explicitly instead of
/// relying on implicit fallback, which differs per platform: Android resolves
/// it via Noto CJK, but a Linux or Windows desktop may not.
class AppFonts {
  const AppFonts._();

  static const body = 'Inter';
  static const display = 'SpaceGrotesk';
  static const mono = 'monospace';

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

/// 4px spacing grid.
class Gap {
  const Gap._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 32.0;
}

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
      // Display styles use Space Grotesk per the design system.
      headlineLarge: TextStyle(
        fontFamily: AppFonts.display,
        fontFamilyFallback: AppFonts.cjkFallback,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
        color: palette.text,
      ),
      headlineMedium: TextStyle(
        fontFamily: AppFonts.display,
        fontFamilyFallback: AppFonts.cjkFallback,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: palette.text,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
      bodyMedium: TextStyle(fontSize: 13, height: 1.45, color: palette.text),
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
      contentTextStyle: TextStyle(color: palette.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? palette.surface : palette.surface2,
      hintStyle: TextStyle(color: palette.faint, fontSize: 13),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.violet, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.violetSoft,
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.violetSoft,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.violet.withValues(alpha: .20),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: palette.text),
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
TextStyle monoStyle({
  required Color color,
  double size = 12,
  FontWeight weight = FontWeight.w500,
}) =>
    TextStyle(
      fontFamily: AppFonts.mono,
      // The config preview and node rows can carry Chinese names.
      fontFamilyFallback: AppFonts.cjkFallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: -0.2,
    );

/// Colour for a latency reading: mint fast, amber usable, danger slow/failed.
Color latencyColor(AppPalette palette, int? latencyMs) {
  if (latencyMs == null) return palette.faint;
  if (latencyMs < 0) return palette.danger;
  if (latencyMs < 120) return palette.mint;
  if (latencyMs < 260) return palette.amber;
  return palette.danger;
}
