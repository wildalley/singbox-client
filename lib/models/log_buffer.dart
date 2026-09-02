/// Fixed-capacity log store with O(1) append and no copy on read.
///
/// The engine can emit hundreds of lines in a burst — one per connection at debug
/// level — and the naive shape of this costs O(n) twice per line: `removeRange`
/// to drop the oldest shifts the whole array, and handing the UI a
/// `List.unmodifiable` copies it again on every build. At 500 entries that is
/// measurable, and it is paid per line exactly when lines are arriving fastest.
///
/// A ring fixes both. Appending overwrites the oldest slot instead of shifting,
/// and reads go through this object rather than a copy of it.
///
/// It is a [List] view rather than an [Iterable] because `ListView.builder` reads
/// by index, and an iterable would make each row an O(n) walk.
library;

import 'dart:collection';

/// A read-only, fixed-capacity list that drops its oldest entry when full.
///
/// Mutation goes through [add] and [clear]; the [List] setters throw, so a caller
/// handed one of these cannot reorder or resize what the buffer owns.
class RingBuffer<T> extends ListBase<T> {
  RingBuffer(this.capacity)
      : assert(capacity > 0),
        _slots = List<T?>.filled(capacity, null);

  /// Most entries kept. Older ones are overwritten.
  final int capacity;

  /// Backing store, allocated once at [capacity] and then reused. The buffer
  /// never grows, so a long session does not creep.
  final List<T?> _slots;

  /// Index in [_slots] of the oldest entry.
  var _start = 0;

  var _length = 0;

  @override
  int get length => _length;

  /// Refused rather than implemented: [ListBase] would otherwise give callers
  /// `add`, `insert` and `removeLast` for free, and each would break the ring's
  /// invariants in a way that shows up as entries in the wrong order much later.
  @override
  set length(int value) => throw UnsupportedError(
        'RingBuffer has a fixed capacity; use add or clear',
      );

  @override
  T operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', null, _length);
    }
    return _slots[(_start + index) % capacity] as T;
  }

  @override
  void operator []=(int index, T value) => throw UnsupportedError(
        'RingBuffer is read-only; use add',
      );

  /// Appends [value], dropping the oldest entry when already at [capacity].
  ///
  /// O(1) either way: at capacity the write lands on the slot the oldest entry
  /// occupied and the window slides forward.
  @override
  void add(T value) {
    if (_length < capacity) {
      _slots[(_start + _length) % capacity] = value;
      _length++;
      return;
    }
    _slots[_start] = value;
    _start = (_start + 1) % capacity;
  }

  /// Appends each of [iterable] through [add].
  ///
  /// Overridden because [ListBase.addAll] does not use [add] — it grows the list
  /// with `length++` and assigns through `[]=`, both of which this class refuses.
  /// Inherited, it throws on the first element.
  @override
  void addAll(Iterable<T> iterable) {
    for (final value in iterable) {
      add(value);
    }
  }

  @override
  void clear() {
    // Nulled rather than just reset, so the entries become collectable instead of
    // being pinned by a buffer that is logically empty.
    _slots.fillRange(0, _slots.length, null);
    _start = 0;
    _length = 0;
  }
}
