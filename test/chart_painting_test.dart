/// The shared chart geometry: crisp hairlines, and a curve through the samples.
///
/// Both were wrong in a way that looked like a rendering artefact rather than a
/// bug. The rules were asked for at fractional device pixels, so they drew as a
/// smear of a colour that is only a tenth opaque to begin with; and the curve was
/// a corner-cutting quadratic that never reached a data point, so it drew a
/// traffic burst at about half its height. The second is the one worth a test:
/// it under-reported the measurement while still looking like a chart.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/ui/chart_painting.dart';

/// Samples the path's vertical extent by walking its metrics.
({double minY, double maxY}) extent(Path path) {
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d <= metric.length; d += 0.5) {
      final y = metric.getTangentForOffset(d)!.position.dy;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  return (minY: minY, maxY: maxY);
}

/// How close the path comes to [point].
double closestApproach(Path path, Offset point) {
  var best = double.infinity;
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d <= metric.length; d += 0.25) {
      final at = metric.getTangentForOffset(d)!.position;
      final distance = (at - point).distance;
      if (distance < best) best = distance;
    }
  }
  return best;
}

void main() {
  group('smoothThrough', () {
    test('passes through a spike instead of cutting it', () {
      // A single tall sample between two idle ones — one second of download in
      // an otherwise quiet minute, which is exactly the shape the traffic chart
      // exists to show. On a 100-tall plot the old midpoint curve reached about
      // y=50 for this; the peak has to actually be at the peak.
      const peak = Offset(20, 0);
      final path = smoothThrough(
        const [Offset(0, 100), peak, Offset(40, 100)],
        minY: 0,
        maxY: 100,
      );

      expect(closestApproach(path, peak), lessThan(0.5));
    });

    test('passes through every sample of a longer series', () {
      final points = [
        for (var i = 0; i < 12; i++)
          Offset(i * 10, i.isEven ? 20.0 : 80.0),
      ];
      final path = smoothThrough(points, minY: 0, maxY: 100);

      for (final point in points) {
        expect(
          closestApproach(path, point),
          lessThan(0.5),
          reason: 'missed $point',
        );
      }
    });

    test('stays inside the plot when a burst would overshoot it', () {
      // A spline through a sharp rise overshoots on the approach. Unclamped that
      // puts the curve above the top of the box, or below the baseline where it
      // would be drawn over the panel beneath.
      final path = smoothThrough(
        const [
          Offset(0, 100),
          Offset(10, 100),
          Offset(20, 0),
          Offset(30, 0),
          Offset(40, 100),
        ],
        minY: 0,
        maxY: 100,
      );

      final bounds = extent(path);
      expect(bounds.minY, greaterThanOrEqualTo(-0.01));
      expect(bounds.maxY, lessThanOrEqualTo(100.01));
    });

    test('degenerate inputs do not throw', () {
      // A chart is built before its history has two samples in it.
      expect(extent(smoothThrough(const [], minY: 0, maxY: 10)).minY,
          double.infinity);
      final single = smoothThrough(const [Offset(1, 2)], minY: 0, maxY: 10);
      expect(single.computeMetrics().isEmpty, isTrue, reason: 'no length');
      final pair = smoothThrough(
        const [Offset(0, 10), Offset(10, 0)],
        minY: 0,
        maxY: 10,
      );
      expect(closestApproach(pair, const Offset(10, 0)), lessThan(0.5));
    });
  });

  group('crispLine', () {
    test('centres a hairline inside one device pixel', () {
      // At ratio 1 a 1px stroke has to sit at something.5 to cover exactly one
      // row; at 40.67 it straddles two and each gets part of the colour.
      expect(crispLine(40.67, 1), 41.5);
      expect(crispLine(61, 1), 61.5);
    });

    test('scales with the ratio', () {
      // On a 2x display a device pixel is half a logical one, so the centre
      // lands on a quarter.
      expect(crispLine(40.67, 2), closeTo(40.75, 1e-9));
      expect(crispLine(10, 3), closeTo(10 + 1 / 6, 1e-9));
    });
  });

  group('snapEdge', () {
    test('puts an edge on a device pixel boundary', () {
      expect(snapEdge(12.4, 1), 12);
      expect(snapEdge(12.6, 1), 13);
      expect(snapEdge(12.4, 2), closeTo(12.5, 1e-9));
    });
  });
}
