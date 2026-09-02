/// [RingBuffer], which the log store is built on.
///
/// The interesting cases are all at and past capacity: that is where the old
/// implementation paid an O(n) shift per line, and where an off-by-one in the
/// index arithmetic would silently reorder the log rather than crash.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/models/log_buffer.dart';

void main() {
  test('reads back in insertion order below capacity', () {
    final buffer = RingBuffer<int>(5)..addAll([1, 2, 3]);

    expect(buffer.length, 3);
    expect(buffer.toList(), [1, 2, 3]);
  });

  test('drops the oldest entry once full', () {
    final buffer = RingBuffer<int>(3)..addAll([1, 2, 3, 4]);

    expect(buffer.length, 3);
    expect(buffer.toList(), [2, 3, 4]);
  });

  test('stays in order after wrapping several times', () {
    // The off-by-one this is really guarding: an index that is wrong by one
    // modulo the capacity does not throw, it just reorders the log — and a log
    // whose lines are out of order is worse than one that is missing lines.
    final buffer = RingBuffer<int>(4);
    for (var i = 0; i < 14; i++) {
      buffer.add(i);
    }

    expect(buffer.toList(), [10, 11, 12, 13]);
  });

  test('indexing matches iteration at every position', () {
    // ListView.builder reads by index while everything else iterates; the two
    // have to agree or the rows shown are not the rows counted.
    final buffer = RingBuffer<int>(4);
    for (var i = 0; i < 9; i++) {
      buffer.add(i);
    }

    final byIndex = [for (var i = 0; i < buffer.length; i++) buffer[i]];
    expect(byIndex, buffer.toList());
  });

  test('capacity one keeps only the last entry', () {
    final buffer = RingBuffer<int>(1)..addAll([1, 2, 3]);

    expect(buffer.toList(), [3]);
  });

  test('an out-of-range index throws rather than reading a stale slot', () {
    // The slots outlive the entries that were in them, so an unchecked read past
    // the length would return a dropped log line as though it were current.
    final buffer = RingBuffer<int>(3)..addAll([1, 2]);

    expect(() => buffer[2], throwsRangeError);
    expect(() => buffer[-1], throwsRangeError);
  });

  test('clear empties it and lets it fill again', () {
    final buffer = RingBuffer<int>(3)..addAll([1, 2, 3]);

    buffer.clear();
    expect(buffer, isEmpty);

    buffer.addAll([4, 5]);
    expect(buffer.toList(), [4, 5]);
  });

  test('the list setters are refused', () {
    // ListBase hands these out for free, and each one would corrupt the ring in
    // a way that only shows up as misordered entries much later.
    final buffer = RingBuffer<int>(3)..addAll([1, 2, 3]);

    expect(() => buffer[0] = 9, throwsUnsupportedError);
    expect(() => buffer.length = 1, throwsUnsupportedError);
  });

  test('appending is O(1) at capacity, not a shift', () {
    // The whole reason this class exists. A shift-based store doubles its
    // per-line cost when capacity doubles; this one should not move.
    int microsFor(int capacity) {
      final buffer = RingBuffer<int>(capacity);
      for (var i = 0; i < capacity; i++) {
        buffer.add(i);
      }
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20000; i++) {
        buffer.add(i);
      }
      return (watch..stop()).elapsedMicroseconds;
    }

    // Warm up, so the first measurement does not carry JIT cost.
    microsFor(500);
    final small = microsFor(500);
    final large = microsFor(8000);

    // Sixteen times the capacity. A shift would be far slower; anything within a
    // small factor here is scheduler noise rather than a trend.
    expect(
      large,
      lessThan(small * 4 + 2000),
      reason: 'append looks O(n): 500 took ${small}us, 8000 took ${large}us',
    );
  });
}
