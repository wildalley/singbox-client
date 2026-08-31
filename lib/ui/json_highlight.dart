/// Syntax colouring for the read-only generated-config preview.
library;

import 'package:flutter/painting.dart';

import 'theme.dart';

/// Splits [source] into coloured spans: object keys, string values, numbers and
/// the `true`/`false`/`null` literals each get their own colour, everything else
/// (braces, commas, whitespace) keeps the base colour.
///
/// This is a scanner, not a parser, and it never rejects input. The preview has
/// to render whatever the builder produced — including output we would consider
/// malformed, since spotting that is the reason to look at this view at all.
/// Every character of [source] ends up in exactly one span, so the indentation
/// the encoder emitted survives untouched.
List<TextSpan> highlightJson(String source, AppPalette palette) {
  final key = TextStyle(color: palette.sky);
  final string = TextStyle(color: palette.mint);
  final number = TextStyle(color: palette.amber);
  final literal = TextStyle(color: palette.violetSoft);
  final punctuation = TextStyle(color: palette.faint);

  final spans = <TextSpan>[];
  final plain = StringBuffer();

  void flush() {
    if (plain.isEmpty) return;
    spans.add(TextSpan(text: plain.toString(), style: punctuation));
    plain.clear();
  }

  void emit(String text, TextStyle style) {
    flush();
    spans.add(TextSpan(text: text, style: style));
  }

  var i = 0;
  while (i < source.length) {
    final char = source[i];

    if (char == '"') {
      final end = _endOfString(source, i);
      // A string is a key only when a colon follows it. Values that happen to
      // look like keys (a bare string in an array) stay value-coloured.
      emit(source.substring(i, end), _colonFollows(source, end) ? key : string);
      i = end;
      continue;
    }

    if (_startsNumber(source, i)) {
      final end = _endOfNumber(source, i);
      emit(source.substring(i, end), number);
      i = end;
      continue;
    }

    final word = _literalAt(source, i);
    if (word != null) {
      emit(word, literal);
      i += word.length;
      continue;
    }

    plain.write(char);
    i++;
  }

  flush();
  return spans;
}

/// Index just past the closing quote of the string starting at [start].
///
/// Returns the end of [source] for an unterminated string so the caller still
/// makes progress instead of looping.
int _endOfString(String source, int start) {
  var i = start + 1;
  while (i < source.length) {
    final char = source[i];
    if (char == r'\') {
      i += 2;
      continue;
    }
    if (char == '"') return i + 1;
    i++;
  }
  return source.length;
}

bool _colonFollows(String source, int from) {
  for (var i = from; i < source.length; i++) {
    final char = source[i];
    if (char == ' ' || char == '\t' || char == '\n' || char == '\r') continue;
    return char == ':';
  }
  return false;
}

bool _startsNumber(String source, int at) {
  if (_isDigit(source[at])) return true;
  // A leading minus only starts a number when a digit follows; a stray dash in
  // punctuation position stays punctuation.
  return source[at] == '-' &&
      at + 1 < source.length &&
      _isDigit(source[at + 1]);
}

int _endOfNumber(String source, int start) {
  var i = start;
  if (source[i] == '-') i++;
  while (i < source.length && _isDigit(source[i])) {
    i++;
  }
  if (i < source.length && source[i] == '.') {
    i++;
    while (i < source.length && _isDigit(source[i])) {
      i++;
    }
  }
  if (i < source.length && (source[i] == 'e' || source[i] == 'E')) {
    var j = i + 1;
    if (j < source.length && (source[j] == '+' || source[j] == '-')) j++;
    // Only consume the exponent if it actually has digits, so `1e` keeps the
    // `e` out of the number span rather than swallowing a malformed tail.
    if (j < source.length && _isDigit(source[j])) {
      i = j;
      while (i < source.length && _isDigit(source[i])) {
        i++;
      }
    }
  }
  return i;
}

/// The JSON literal starting exactly at [at], or null.
String? _literalAt(String source, int at) {
  for (final word in const ['true', 'false', 'null']) {
    if (!source.startsWith(word, at)) continue;
    final after = at + word.length;
    // Guard against matching the head of a longer bare word.
    if (after < source.length && _isLetter(source[after])) continue;
    return word;
  }
  return null;
}

bool _isDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

bool _isLetter(String char) {
  final code = char.codeUnitAt(0) | 0x20;
  return code >= 0x61 && code <= 0x7a;
}
