/// The launcher icon and the launch splash live in XML and PNG, so neither the
/// analyzer nor the widget tests can see them drift away from the palette they
/// were drawn from — or, for the icon, out of the safe circle every launcher
/// mask crops to. These read the shipped resources rather than restating them.
library;

import 'dart:io';
import 'dart:math' show max;
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/ui/theme.dart';

const _res = 'android/app/src/main/res';

String _xml(String path) => File('$_res/$path').readAsStringSync();

/// Every `#AARRGGBB` literal in a resource, in document order.
List<Color> _colors(String xml) => RegExp(r'#([0-9A-Fa-f]{8})')
    .allMatches(xml)
    .map((match) => Color(int.parse(match.group(1)!, radix: 16)))
    .toList();

double _ratio(Color fg, Color bg) {
  final a = fg.computeLuminance();
  final b = bg.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('launcher icon', () {
    test('is drawn from the palette, not from new colours', () {
      final palette = AppPalette.dark;
      final background = _colors(_xml('drawable/ic_launcher_background.xml'));
      final foreground = _colors(_xml('drawable/ic_launcher_foreground.xml'));

      expect(background.first.toARGB32(), palette.bg.toARGB32(),
          reason: 'the plate is the app background');
      // The glow's two stops are the same violet at 22% and 0%.
      for (final stop in background.skip(1)) {
        expect(stop.withValues(alpha: 1).toARGB32(), palette.violet.toARGB32());
      }
      expect(foreground[0].toARGB32(), palette.violetSoft.toARGB32(),
          reason: 'the dial ring: violet is fill-only, foregrounds take '
              'violetSoft');
      for (final live in foreground.skip(1)) {
        expect(live.toARGB32(), palette.mint.toARGB32(),
            reason: 'the filled segment and the node are the live colour');
      }
    });

    test('the mark clears 3:1 against its own glow', () {
      // The glow sits on the background layer, so it paints *behind* the mark
      // rather than through it — but it still lifts what the mark is measured
      // against, and it is brightest dead centre, under the node. That blend is
      // the worst case, not the bare background.
      final glow = _colors(_xml('drawable/ic_launcher_background.xml'))[1];
      final worst = Color.alphaBlend(glow, AppPalette.dark.bg);
      for (final color in _colors(_xml('drawable/ic_launcher_foreground.xml'))) {
        expect(_ratio(color, worst), greaterThanOrEqualTo(3),
            reason: 'icon-sized shapes need 3:1');
      }
    });

    test('the mark stays inside the adaptive safe circle', () {
      // A launcher may mask the 108dp canvas down to a 66dp circle, and only
      // that circle is guaranteed to survive. Anything drawn past r=33 can be
      // cut off on some devices and not others.
      for (final file in ['ic_launcher_foreground', 'ic_launcher_monochrome']) {
        final xml = _xml('drawable/$file.xml');
        expect(RegExp(r'viewport(Width|Height)="108"').allMatches(xml).length, 2,
            reason: '$file must use the 108dp adaptive canvas');

        // Radii come from the arc commands; a stroke straddles its path, so
        // half of it reaches further out than the radius does.
        final radii = RegExp(r'[Aa]([\d.]+),([\d.]+)')
            .allMatches(xml)
            .map((match) => double.parse(match.group(1)!));
        final strokes = RegExp(r'strokeWidth="([\d.]+)"')
            .allMatches(xml)
            .map((match) => double.parse(match.group(1)!));
        final widest = strokes.isEmpty ? 0.0 : strokes.reduce(max);
        for (final radius in radii) {
          expect(radius + widest / 2, lessThanOrEqualTo(33),
              reason: '$file reaches outside the safe circle');
        }
      }
    });

    test('the pre-26 fallback ships at every density', () {
      // minSdk is 24, so Android 7.x still takes the PNGs; the adaptive vector
      // only answers from 26 up. Sizes are Android's launcher-icon ladder.
      const expected = {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      };
      for (final name in ['ic_launcher', 'ic_launcher_round']) {
        for (final entry in expected.entries) {
          final file = File('$_res/mipmap-${entry.key}/$name.png');
          expect(file.existsSync(), isTrue,
              reason: '$name missing at ${entry.key}');
          // IHDR: 8-byte signature, 4-byte length, 4-byte type, then w and h as
          // big-endian 32-bit ints.
          final header = ByteData.sublistView(file.readAsBytesSync(), 16, 24);
          expect(header.getUint32(0), entry.value,
              reason: '$name ${entry.key} width');
          expect(header.getUint32(4), entry.value,
              reason: '$name ${entry.key} height');
        }
      }
    });

    test('both entry points resolve, and the round one is really round', () {
      // The manifest names two icons; API 25 is the only level that asks for
      // the round one, and it gets a PNG, so the two sets must not be copies of
      // each other — a square plate inside a circular hole is the bug this
      // guards.
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
      expect(manifest,
          contains('android:roundIcon="@mipmap/ic_launcher_round"'));
      for (final name in ['ic_launcher', 'ic_launcher_round']) {
        final xml = _xml('mipmap-anydpi-v26/$name.xml');
        for (final layer in ['background', 'foreground', 'monochrome']) {
          expect(
              xml,
              contains('<$layer android:drawable="@drawable/'
                  'ic_launcher_$layer"'),
              reason: '$name is missing its $layer layer');
        }
      }
      expect(
        File('$_res/mipmap-xxxhdpi/ic_launcher.png').readAsBytesSync(),
        isNot(File('$_res/mipmap-xxxhdpi/ic_launcher_round.png')
            .readAsBytesSync()),
      );
    });
  });

  group('launch splash', () {
    test('is the app background in both ui modes, never the template white', () {
      // The window the OS paints before Flutter's first frame. It shipped as
      // the template's white, which flashed in front of a near-black app.
      final day = _colors(_xml('values/colors.xml'));
      final night = _colors(_xml('values-night/colors.xml'));
      expect(day.single.toARGB32(), AppPalette.light.bg.toARGB32());
      expect(night.single.toARGB32(), AppPalette.dark.bg.toARGB32());
    });

    test('every window background points at that colour', () {
      // Three of them: the splash drawable, and NormalTheme in each ui mode —
      // the last one is what shows between the splash and the first frame.
      expect(_xml('drawable/launch_background.xml'),
          contains('android:drawable="@color/splash_background"'));
      for (final styles in ['values/styles.xml', 'values-night/styles.xml']) {
        final xml = _xml(styles);
        expect(xml, isNot(contains('?android:colorBackground')),
            reason: '$styles would inherit the parent theme\'s white or black');
        expect(
          RegExp(r'name="android:windowBackground">@(color/splash_background'
                  r'|drawable/launch_background)<')
              .allMatches(xml)
              .length,
          2,
          reason: '$styles must set both LaunchTheme and NormalTheme',
        );
      }
    });

    test('the drawable has no API-qualified twin left to fall out of sync', () {
      // minSdk is 24, so the template's drawable-v21/ copy always won and the
      // unqualified one was dead. Only one file now.
      expect(Directory('$_res/drawable-v21').existsSync(), isFalse);
    });
  });
}
