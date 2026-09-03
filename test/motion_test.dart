/// The motion primitives added for the Synapse V4 interaction pass.
///
/// These three carry rules that are easy to break without noticing, because a
/// broken one still renders the right pixels once it has settled: a counter that
/// counts up from zero on first paint, a reorder slide that mistakes a scroll for
/// a reorder, or an animation that ignores "reduce motion". Each is asserted
/// here rather than left to a screenshot, which only ever sees the resting
/// frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/main.dart';
import 'package:singbox_client/models/node_sort.dart';
import 'package:singbox_client/models/proxy_state.dart' show formatBytes;
import 'package:singbox_client/ui/theme.dart';
import 'package:singbox_client/ui/widgets.dart';

import 'widget_test.dart' show buildState, node;

/// Wraps [child] in the minimum needed for these widgets to build.
///
/// [reduceMotion] drives the same flag the accessibility setting sets, which is
/// what `motionOf` reads.
Widget host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Scaffold(body: Center(child: child)),
      ),
    );

String shownText(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text)).data!;

void main() {
  group('AnimatedCount', () {
    testWidgets('shows its value on the first frame', (tester) async {
      // The reason Tween.begin is left null. A screen that opens on a total of
      // 4.0 GB should read 4.0 GB, not sweep up to it from zero — and every
      // golden is recorded a few hundred ms after pumpWidget, so a first-build
      // animation would also make those snapshots depend on their own timing.
      await tester.pumpWidget(
        host(
          AnimatedCount(
            value: 4 * 1024 * 1024 * 1024,
            format: formatBytes,
            style: const TextStyle(),
          ),
        ),
      );

      expect(shownText(tester), '4.0 GB');
    });

    testWidgets('counts to a new value and lands on it exactly', (tester) async {
      Widget at(int value) => host(
            AnimatedCount(
              value: value,
              format: (value) => '$value',
              style: const TextStyle(),
            ),
          );

      await tester.pumpWidget(at(0));
      await tester.pumpWidget(at(1000));

      // Mid-flight: moved off the old value, not yet at the new one.
      await tester.pump(const Duration(milliseconds: 100));
      final midway = int.parse(shownText(tester));
      expect(midway, greaterThan(0));
      expect(midway, lessThan(1000));

      // The tween has to arrive on the integer it was given, not near it: this
      // is a byte total, and a readout that settles on 999 is simply wrong.
      await tester.pumpAndSettle();
      expect(shownText(tester), '1000');
    });

    testWidgets('formats the tweened value, so units roll through',
        (tester) async {
      // formatBytes is applied per frame rather than to the target, which is
      // what carries a total across a unit boundary instead of cutting to it.
      Widget at(int value) => host(
            AnimatedCount(
              value: value,
              format: formatBytes,
              style: const TextStyle(),
            ),
          );

      await tester.pumpWidget(at(1000));
      await tester.pumpWidget(at(4 * 1024 * 1024));

      // Sampled across the whole tween rather than at one chosen instant: the
      // curve is a strong ease-out, so which frame happens to be in the KB range
      // is a property of the curve and not something worth pinning here.
      final seen = <String>[];
      for (var elapsed = Duration.zero;
          elapsed < const Duration(milliseconds: 500);
          elapsed += const Duration(milliseconds: 16)) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(shownText(tester));
      }

      expect(
        seen.where((text) => text.endsWith('KB')),
        isNotEmpty,
        reason: 'never passed through KB on the way from 1000 B to 4 MB: $seen',
      );
      await tester.pumpAndSettle();
      expect(shownText(tester), '4.0 MB');
    });

    testWidgets('lands immediately when motion is reduced', (tester) async {
      Widget at(int value) => host(
            AnimatedCount(
              value: value,
              format: (value) => '$value',
              style: const TextStyle(),
            ),
            reduceMotion: true,
          );

      await tester.pumpWidget(at(0));
      await tester.pumpWidget(at(1000));
      await tester.pump();

      // The update still happens — only the movement is dropped.
      expect(shownText(tester), '1000');
    });
  });

  group('ReorderSlide', () {
    /// The vertical offset [ReorderSlide] is currently painting [key] at.
    double paintedShift(WidgetTester tester, Key key) {
      final transform = tester.widget<Transform>(
        find.ancestor(
          of: find.byKey(key),
          matching: find.byType(Transform),
        ).first,
      );
      return transform.transform.getTranslation().y;
    }

    /// Two rows in [order], each wrapped so it can slide.
    Widget list(List<String> order) => host(
          Column(
            children: [
              for (final id in order)
                ReorderSlide(
                  key: ValueKey(id),
                  child: SizedBox(height: 40, child: Text(id, key: Key('t$id'))),
                ),
            ],
          ),
        );

    testWidgets('does not move on first build', (tester) async {
      // A freshly built list has no previous position to have come from. Without
      // this every navigation to the page would set the rows sliding.
      await tester.pumpWidget(list(['a', 'b']));
      await tester.pump();

      expect(paintedShift(tester, const Key('ta')), 0);
      expect(paintedShift(tester, const Key('tb')), 0);
    });

    testWidgets('slides from the old position and settles at the new one',
        (tester) async {
      await tester.pumpWidget(list(['a', 'b']));
      await tester.pump();

      // 'a' and 'b' swap, as they do when a latency sweep re-sorts the list.
      await tester.pumpWidget(list(['b', 'a']));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Each row is drawn offset back toward where it was: 'a' moved down a row,
      // so it is lifted up, and 'b' the other way. The signs being opposite is
      // what makes this a swap rather than the whole list shifting.
      final a = paintedShift(tester, const Key('ta'));
      final b = paintedShift(tester, const Key('tb'));
      expect(a, lessThan(0));
      expect(b, greaterThan(0));

      await tester.pumpAndSettle();
      expect(paintedShift(tester, const Key('ta')), 0);
      expect(paintedShift(tester, const Key('tb')), 0);
    });

    testWidgets('does not slide when motion is reduced', (tester) async {
      Widget at(List<String> order) => MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    for (final id in order)
                      ReorderSlide(
                        key: ValueKey(id),
                        child: SizedBox(
                          height: 40,
                          child: Text(id, key: Key('t$id')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );

      await tester.pumpWidget(at(['a', 'b']));
      await tester.pump();
      await tester.pumpWidget(at(['b', 'a']));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(paintedShift(tester, const Key('ta')), 0);
      expect(paintedShift(tester, const Key('tb')), 0);
    });

    testWidgets('clamps a move too long to follow', (tester) async {
      // A latency sort can send a row most of the way down a long list. Drawn
      // from its true origin it would cross the viewport in one 300ms sweep,
      // over the top of every row in between.
      Widget list(List<String> order) => host(
            Column(
              children: [
                for (final id in order)
                  ReorderSlide(
                    key: ValueKey(id),
                    child: SizedBox(height: 40, child: Text(id, key: Key('t$id'))),
                  ),
              ],
            ),
          );

      final many = [for (var i = 0; i < 14; i++) 'n$i'];
      await tester.pumpWidget(list(many));
      await tester.pump();

      // The first row goes to the back: 13 rows of travel, ~520px.
      await tester.pumpWidget(list([...many.skip(1), many.first]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final travelled = paintedShift(tester, const Key('tn0')).abs();
      expect(travelled, greaterThan(0), reason: 'still animates');
      expect(travelled, lessThanOrEqualTo(240), reason: 'but not the full 520');

      await tester.pumpAndSettle();
      expect(paintedShift(tester, const Key('tn0')), 0);
    });

    testWidgets('a scroll is not a reorder', (tester) async {
      // The position is read from the parent, not from the screen. Were it
      // global, flicking the list would register as every row moving at once and
      // they would all fight the scroll with a slide.
      Widget scrollable() => host(
            SizedBox(
              height: 120,
              child: ListView(
                children: [
                  for (final id in ['a', 'b', 'c', 'd', 'e'])
                    ReorderSlide(
                      key: ValueKey(id),
                      child: SizedBox(
                        height: 40,
                        child: Text(id, key: Key('t$id')),
                      ),
                    ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(scrollable());
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -60));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(paintedShift(tester, const Key('tb')), 0);
      expect(paintedShift(tester, const Key('tc')), 0);
    });
  });

  group('the nodes page', () {
    testWidgets('slides its rows when a latency sort reorders them',
        (tester) async {
      // The isolated ReorderSlide tests above prove the mechanism. This proves
      // it is actually wired into the page that needs it, and that the rows are
      // laid out by a parent it can measure against — a ReorderSlide whose
      // parent does not position its children would silently never animate.
      final harness = await buildState(
        nodes: [
          node('a', 'Alpha').copyWith(latencyMs: 300),
          node('b', 'Bravo').copyWith(latencyMs: 40),
        ],
      );
      addTearDown(harness.state.dispose);

      await tester.pumpWidget(SingBoxApp(state: harness.state));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.hub_outlined));
      await tester.pumpAndSettle();

      /// The offset the row carrying [name] is painted at.
      ///
      /// Scoped to the row's [ReorderSlide] and taken outermost-first: [Panel]
      /// has an AnimatedScale of its own for the press state, so the nearest
      /// Transform above the text is that one, not the slide's.
      double shiftOf(String name) {
        final transform = tester.widget<Transform>(
          find.descendant(
            of: find.ancestor(
              of: find.text(name),
              matching: find.byType(ReorderSlide),
            ),
            matching: find.byType(Transform),
          ).first,
        );
        return transform.transform.getTranslation().y;
      }

      expect(shiftOf('Alpha'), 0, reason: 'settled before the sort');

      // Bravo is the faster node, so sorting by latency lifts it above Alpha.
      await harness.state.setNodeSort(NodeSort.latency);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(shiftOf('Alpha'), lessThan(0), reason: 'Alpha moved down a row');
      expect(shiftOf('Bravo'), greaterThan(0), reason: 'Bravo moved up a row');

      await tester.pumpAndSettle();
      expect(shiftOf('Alpha'), 0);
      expect(shiftOf('Bravo'), 0);
    });
  });

  group('SegmentedChoice', () {
    /// Where the selection indicator is *currently drawn* within the track.
    ///
    /// Read off the [Align] that [AnimatedAlign] builds each frame, not off
    /// AnimatedAlign itself — its own `alignment` field is the target it is
    /// heading for, so asserting on that would pass even if nothing moved.
    double indicatorX(WidgetTester tester) {
      final align = tester.widget<Align>(
        find.descendant(
          of: find.byType(AnimatedAlign),
          matching: find.byType(Align),
        ),
      );
      return (align.alignment as Alignment).x;
    }

    Widget choice(String selected) => host(
          SegmentedChoice<String>(
            values: const ['one', 'two', 'three'],
            selected: selected,
            labelOf: (value) => value,
            onChanged: (_) {},
          ),
        );

    testWidgets('puts the indicator on the selected segment', (tester) async {
      // -1, 0, 1 across three segments: the ends sit flush and the middle is
      // centred, which is what keeps the pill concentric with its own label.
      for (final (value, expected) in [('one', -1.0), ('two', 0.0), ('three', 1.0)]) {
        await tester.pumpWidget(choice(value));
        // Settled, because the tree persists across iterations: read on the
        // first frame this would still be travelling from the previous segment.
        await tester.pumpAndSettle();
        expect(indicatorX(tester), expected, reason: 'selected $value');
      }
    });

    testWidgets('slides between segments rather than jumping', (tester) async {
      await tester.pumpWidget(choice('one'));
      await tester.pumpWidget(choice('three'));
      await tester.pump(const Duration(milliseconds: 60));

      // Caught in transit between the two ends.
      final travelling = indicatorX(tester);
      expect(travelling, greaterThan(-1));
      expect(travelling, lessThan(1));

      await tester.pumpAndSettle();
      expect(indicatorX(tester), 1);
    });

    testWidgets('a selection outside the values does not throw',
        (tester) async {
      // Guards the indexOf: a caller can hold a value that has since been
      // filtered out of the list, and a -1 index would place the indicator off
      // the track or crash the alignment.
      await tester.pumpWidget(choice('gone'));
      expect(indicatorX(tester), 0);
      expect(tester.takeException(), isNull);
    });
  });
}
