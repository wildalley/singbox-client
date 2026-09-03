/// Canvas helpers shared by the charts.
///
/// Both chart painters live in different files — [Sparkline] in `widgets.dart`
/// with the primitives, the flow chart in `components.dart` with the dashboard —
/// but they draw the same two things and were getting both wrong in the same
/// way. The rules and the curve live here so there is one answer.
library;

import 'dart:ui';

/// Centres a one-device-pixel line on [y] so it draws crisp.
///
/// A canvas works in logical pixels, so a hairline asked for at y=40.67 lands
/// across two rows of device pixels and each gets a fraction of the colour. On
/// the chart rules — drawn in a border colour that is already only a tenth
/// opaque — halving that again is the difference between a faint line and a
/// grey smudge. Snapping to the middle of one device pixel puts the whole
/// stroke in one row.
///
/// [dpr] is the device pixel ratio, which a painter has to be handed: it has no
/// BuildContext to read it from.
double crispLine(double y, double dpr) => (y * dpr).round() / dpr + .5 / dpr;

/// Aligns [value] to the nearest device pixel boundary.
///
/// For edges that should be sharp rather than centred — the sides of a bar.
double snapEdge(double value, double dpr) => (value * dpr).round() / dpr;

/// A smooth path through every one of [points].
///
/// A Catmull-Rom spline, converted segment by segment to the cubic Béziers a
/// [Path] takes. The tangent at each point is set by its two neighbours, which
/// is what makes the curve pass *through* the samples.
///
/// The obvious cheaper trick — quadratics from each point to the midpoint of the
/// next, with the sample as the control — is what this replaces. That curve only
/// ever reaches the midpoints, so a one-sample spike is drawn at about half its
/// height. On a traffic chart, where a burst is a single tall sample, it quietly
/// flattened the very thing the chart is for.
///
/// Control points are clamped into [minY]..[maxY]. A spline through a sharp rise
/// overshoots on the approach, and without the clamp a burst pushes the curve
/// out through the top of the plot or below its baseline.
Path smoothThrough(
  List<Offset> points, {
  required double minY,
  required double maxY,
}) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return path;
  }

  double clamp(double y) => y < minY ? minY : (y > maxY ? maxY : y);

  for (var i = 0; i < points.length - 1; i++) {
    // The segment being drawn is current -> next; previous and after set the
    // tangents at its ends. At the ends of the series the missing neighbour is
    // the endpoint itself, which makes the curve leave and arrive level.
    final previous = i == 0 ? points[0] : points[i - 1];
    final current = points[i];
    final next = points[i + 1];
    final after = i + 2 < points.length ? points[i + 2] : next;

    // A sixth is the standard Catmull-Rom to Bézier conversion, and gives the
    // uniform spline: tangent at a point is a sixth of the span its neighbours
    // straddle.
    path.cubicTo(
      current.dx + (next.dx - previous.dx) / 6,
      clamp(current.dy + (next.dy - previous.dy) / 6),
      next.dx - (after.dx - current.dx) / 6,
      clamp(next.dy - (after.dy - current.dy) / 6),
      next.dx,
      next.dy,
    );
  }
  return path;
}
