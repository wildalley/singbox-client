/// What a burst of log lines costs the rest of the app.
///
/// The engine emits one line per connection at debug level, so "a burst" is the
/// normal case rather than an edge one. Three things used to scale with it and
/// each is asserted here: a notify per line, an O(n) trim per line, and a copy of
/// the whole log per read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/app_settings.dart';
import 'package:singbox_client/models/log_buffer.dart';

import 'widget_test.dart' show buildState, node;

void main() {
  testWidgets('a burst notifies once, not once per line', (tester) async {
    // 300 lines used to mean 300 rebuilds of MaterialApp and every page under
    // it, inside a single frame the user never saw.
    final harness = await buildState();
    addTearDown(harness.state.dispose);

    var notifies = 0;
    harness.state.addListener(() => notifies++);

    for (var i = 0; i < 300; i++) {
      harness.controller.emitLog('inbound/tun: connection $i');
    }
    // Advances the clock, so the coalesced notification actually fires. A bare
    // pump() does not move time and a zero-duration timer would stay queued.
    await tester.pump(Duration.zero);

    expect(harness.state.logs, hasLength(300), reason: 'no line was dropped');
    expect(
      notifies,
      lessThan(5),
      reason: '$notifies notifications for one burst of 300 lines',
    );
  });

  testWidgets('every line still arrives before the next frame', (tester) async {
    // The coalescing must not make the log lag the engine. A microtask drains
    // before the frame; a millisecond debounce would not.
    final harness = await buildState();
    addTearDown(harness.state.dispose);

    harness.controller.emitLog('first');
    harness.controller.emitLog('second');
    await tester.pump(Duration.zero);

    expect(harness.state.logs.map((entry) => entry.message),
        ['first', 'second']);
  });

  test('the log is capped and drops the oldest line', () async {
    final harness = await buildState();
    addTearDown(harness.state.dispose);

    for (var i = 0; i < 700; i++) {
      harness.controller.emitLog('line $i');
    }
    await ft.pumpEventQueue();

    // Capped, and it is the oldest that went: a log that dropped the newest
    // would hide the error the user came to read.
    expect(harness.state.logs.length, lessThanOrEqualTo(500));
    expect(harness.state.logs.last.message, 'line 699');
  });

  test('reading the log does not copy it', () async {
    // The second O(n) per line. The buffer is already read-only, so the copy was
    // paying for a guarantee it did not need.
    final harness = await buildState();
    addTearDown(harness.state.dispose);

    expect(harness.state.logs, same(harness.state.logs));
    expect(harness.state.logs, isA<RingBuffer<Object?>>());
  });

  test('the log handed to the UI cannot be mutated', () async {
    // What the copy was there for. The buffer refuses the mutating List setters,
    // so handing it out directly is still safe.
    final harness = await buildState();
    addTearDown(harness.state.dispose);
    harness.controller.emitLog('line');
    await ft.pumpEventQueue();

    final logs = harness.state.logs;
    // The two ways a caller could reorder or resize what the state owns. `clear`
    // is deliberately not among them — the buffer implements it, because emptying
    // the log is a thing the app itself does.
    expect(() => logs[0] = logs[0], throwsUnsupportedError);
    expect(() => logs.length = 0, throwsUnsupportedError);
  });

  testWidgets('a burst on another page does not rebuild MaterialApp',
      (tester) async {
    // MaterialApp sits above Theme, Localizations and every page, so rebuilding
    // it was the most expensive thing a log line could do — and it had no reason
    // to, since neither the theme nor the locale had changed.
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    final before = tester.widget<MaterialApp>(find.byType(MaterialApp));

    for (var i = 0; i < 100; i++) {
      harness.controller.emitLog('line $i');
    }
    await tester.pump(Duration.zero);

    // The same widget instance: it was never rebuilt.
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)), same(before));
  });

  testWidgets('changing the theme still rebuilds MaterialApp', (tester) async {
    // The other half of narrowing that listener: it has to still fire for the two
    // settings MaterialApp actually reads.
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    final before = tester.widget<MaterialApp>(find.byType(MaterialApp));

    await harness.state.applySettings(
      harness.state.settings.copyWith(themeMode: AppThemeMode.light),
    );
    await tester.pumpAndSettle();

    final after = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(after, isNot(same(before)));
    expect(after.themeMode, ThemeMode.light);
  });

  _scrollBehaviour();
}
/// Following a live log: the step is jumped, a long catch-up is eased.
void _scrollBehaviour() {
  testWidgets('a new line keeps the view pinned to the bottom', (tester) async {
    tester.view.physicalSize = const Size(760, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();

    for (var i = 0; i < 200; i++) {
      harness.controller.emitLog('line $i');
    }
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    // At the end, not near it: a follow that lags is a follow that shows the
    // wrong lines.
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
  });

  testWidgets('turning follow off leaves the view where it was',
      (tester) async {
    tester.view.physicalSize = const Size(760, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    for (var i = 0; i < 200; i++) {
      harness.controller.emitLog('line $i');
    }
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    // Pause, scroll up to read something, then let more lines arrive.
    await tester.tap(find.byIcon(Icons.vertical_align_bottom));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    final parked = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .pixels;

    for (var i = 0; i < 50; i++) {
      harness.controller.emitLog('more $i');
    }
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    // Unmoved. Yanking a paused log to the bottom is the reason pause exists.
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable).last).position.pixels,
      closeTo(parked, 1),
    );
  });

  testWidgets('turning follow back on returns to the bottom', (tester) async {
    tester.view.physicalSize = const Size(760, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    for (var i = 0; i < 200; i++) {
      harness.controller.emitLog('line $i');
    }
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.vertical_align_bottom));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();

    // Back on: an eased move, so pumpAndSettle has to run it out.
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position;
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
  });
}
