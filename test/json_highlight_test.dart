/// Tests for the config preview's syntax colouring.
///
/// The invariant that matters most is lossless output: the preview renders the
/// generated config, so every character the encoder emitted — including the
/// indentation — has to survive into exactly one span. A highlighter that drops
/// or reorders text would quietly misrepresent what is sent to sing-box.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/ui/json_highlight.dart';
import 'package:singbox_client/ui/theme.dart';

void main() {
  const palette = AppPalette.dark;

  String concat(List<TextSpan> spans) => spans.map((s) => s.text ?? '').join();

  Color? colorOf(List<TextSpan> spans, String text) => spans
      .firstWhere(
        (span) => span.text == text,
        orElse: () => const TextSpan(text: '', style: null),
      )
      .style
      ?.color;

  group('highlightJson', () {
    test('reproduces the source exactly, whitespace included', () {
      const source = '{\n  "tag": "proxy",\n  "mtu": 9000\n}';
      expect(concat(highlightJson(source, palette)), source);
    });

    test('colours keys differently from string values', () {
      final spans = highlightJson('{"tag": "proxy"}', palette);
      expect(colorOf(spans, '"tag"'), palette.sky);
      expect(colorOf(spans, '"proxy"'), palette.mint);
    });

    test('a bare string in an array is a value, not a key', () {
      final spans = highlightJson('["geosite-cn", "geoip-cn"]', palette);
      expect(colorOf(spans, '"geosite-cn"'), palette.mint);
      expect(colorOf(spans, '"geoip-cn"'), palette.mint);
    });

    test('a key is still a key when the colon is on the next line', () {
      final spans = highlightJson('{"tag"\n: "proxy"}', palette);
      expect(colorOf(spans, '"tag"'), palette.sky);
    });

    test('numbers and literals get their own colours', () {
      final spans = highlightJson(
        '{"mtu": 9000, "fake_ip": true, "detour": null, "off": false}',
        palette,
      );
      expect(colorOf(spans, '9000'), palette.amber);
      expect(colorOf(spans, 'true'), palette.violetSoft);
      expect(colorOf(spans, 'null'), palette.violetSoft);
      expect(colorOf(spans, 'false'), palette.violetSoft);
    });

    test('escaped quotes do not end a string early', () {
      const source = r'{"name": "say \"hi\" now"}';
      final spans = highlightJson(source, palette);
      expect(concat(spans), source);
      expect(colorOf(spans, r'"say \"hi\" now"'), palette.mint);
    });

    test('a trailing backslash does not run past the end', () {
      const source = r'{"name": "tail\';
      expect(concat(highlightJson(source, palette)), source);
    });

    test('digits inside a string are not numbers', () {
      final spans = highlightJson('{"server": "1.1.1.1"}', palette);
      expect(colorOf(spans, '"1.1.1.1"'), palette.mint);
      expect(colorOf(spans, '1'), isNull);
    });

    test('literals inside a string are not literals', () {
      final spans = highlightJson('{"mode": "nullify"}', palette);
      expect(colorOf(spans, '"nullify"'), palette.mint);
      expect(colorOf(spans, 'null'), isNull);
    });

    test('a literal is not matched at the head of a longer word', () {
      // Bare `nullable` is not valid JSON, but the preview must still render it
      // rather than colour half of it as a literal.
      final spans = highlightJson('{"x": nullable}', palette);
      expect(colorOf(spans, 'null'), isNull);
      expect(concat(spans), '{"x": nullable}');
    });

    test('negative and fractional numbers stay one span', () {
      final spans = highlightJson('[-1, 2.5, -0.25]', palette);
      expect(colorOf(spans, '-1'), palette.amber);
      expect(colorOf(spans, '2.5'), palette.amber);
      expect(colorOf(spans, '-0.25'), palette.amber);
    });

    test('exponents are consumed only when they carry digits', () {
      expect(colorOf(highlightJson('[1e3]', palette), '1e3'), palette.amber);
      expect(colorOf(highlightJson('[1e-3]', palette), '1e-3'), palette.amber);
      // Malformed: the `e` must not be swallowed into the number span.
      final spans = highlightJson('[1e]', palette);
      expect(colorOf(spans, '1'), palette.amber);
      expect(concat(spans), '[1e]');
    });

    test('a lone dash stays punctuation', () {
      final spans = highlightJson('{"a": -}', palette);
      expect(colorOf(spans, '-'), isNull);
      expect(concat(spans), '{"a": -}');
    });

    test('an unterminated string terminates the scan', () {
      const source = '{"tag": "unclosed';
      expect(concat(highlightJson(source, palette)), source);
    });

    test('empty input yields no spans', () {
      expect(highlightJson('', palette), isEmpty);
    });

    test('every span carries a colour so none inherits by accident', () {
      final spans = highlightJson('{\n  "mtu": 9000\n}', palette);
      expect(spans, isNotEmpty);
      for (final span in spans) {
        expect(span.style?.color, isNotNull,
            reason: 'uncoloured: ${span.text}');
      }
    });
  });
}
