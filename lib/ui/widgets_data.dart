part of 'widgets.dart';

/// Sparkline for the traffic history. Draws a filled area under the line.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.secondColor,
    this.height = 62,
    this.level = false,
  });

  final List<int> values;
  final Color color;

  /// Second stop for the line and fill gradients — pass `palette.sky` next to a
  /// mint series. Left null the chart is drawn in [color] alone.
  final Color? secondColor;
  final double height;

  /// Set for a series that is a standing level (memory in use) rather than a
  /// rate (bytes per second).
  ///
  /// Rates belong on a zero-based scale: an idle second really is nothing, and
  /// the height of the curve is the quantity. A level never visits zero, so the
  /// same scale would pin it to the top of the box and fill the whole rect —
  /// a solid block that looks like a measurement while carrying none. In level
  /// mode the series is scaled to its own min/max instead, so what the curve
  /// shows is the variation, and a steady level reads as a flat line.
  final bool level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        // A painter has no BuildContext, so the baseline colour is passed in.
        painter: _SparklinePainter(
          values,
          color,
          secondColor ?? color,
          context.palette.border,
          level,
          // A painter has no context of its own, and the rules need the ratio to
          // land on whole device pixels.
          MediaQuery.of(context).devicePixelRatio,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(
    this.values,
    this.color,
    this.secondColor,
    this.baselineColor,
    this.level,
    this.dpr,
  );

  final List<int> values;
  final Color color;
  final Color secondColor;
  final Color baselineColor;
  final bool level;
  final double dpr;

  /// Height at which the box gets ruled rather than just underlined.
  ///
  /// The inline strips in the metric cards are 30px: rules there would be graph
  /// paper. The traffic card's chart is twice that, and a single bottom line left
  /// an idle tunnel showing a tall empty box with a hairline under it.
  static const _gridFrom = 48.0;

  /// Matches [TrafficFlowChart]: enough to read height off, not graph paper.
  static const _gridLines = 4;

  @override
  void paint(Canvas canvas, Size size) {
    // Baseline so an idle tunnel still reads as a chart rather than blank space.
    final baseline = Paint()
      ..color = baselineColor
      ..strokeWidth = 1;
    if (size.height >= _gridFrom) {
      // Ruled like the wide layout's flow panel, so a chart with nothing in it
      // yet reads as an empty plot rather than as a panel that failed to draw.
      for (var i = 0; i < _gridLines; i++) {
        // Inset by half a stroke at both ends so the top and bottom rules are
        // drawn whole; centred on the edge itself, half of each falls outside
        // the canvas and they come out fainter than the ones between them.
        final span = size.height - 1;
        final y = crispLine(span - span * i / (_gridLines - 1), dpr);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), baseline);
      }
    } else {
      final y = crispLine(size.height - 1, dpr);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), baseline);
    }

    if (values.length < 2) return;

    final peak = values.reduce((a, b) => a > b ? a : b);
    if (peak <= 0) return;

    final floor = level ? values.reduce((a, b) => a < b ? a : b) : 0;
    final span = peak - floor;
    final usable = size.height - 4;

    double fraction(int value) {
      if (!level) return value / peak;
      // The band floats inside the box: the low sample keeps some fill beneath
      // it and the high sample keeps headroom above, so the curve reads as
      // variation around a level rather than as a bar reaching a limit.
      if (span == 0) return .5;
      return .2 + .6 * (value - floor) / span;
    }

    final step = size.width / (values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(i * step, size.height - fraction(values[i]) * usable),
    ];

    // Through every sample, not past it — see [smoothThrough]. Held inside the
    // box so a burst cannot push the curve out of the plot.
    final line = smoothThrough(points, minY: 1, maxY: size.height - 1);

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);

    // Fill fades down; the two colours are blended horizontally first so the
    // area sits under the line's own gradient instead of fighting it.
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, secondColor, .5)!.withValues(alpha: .26),
            color.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );

    // Left-to-right on the line: oldest sample in [color], newest in
    // [secondColor], so the sweep reads as time passing.
    canvas.drawPath(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: [color, secondColor],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.secondColor != secondColor ||
      oldDelegate.baselineColor != baselineColor ||
      oldDelegate.level != level ||
      oldDelegate.dpr != dpr ||
      !listEquals(oldDelegate.values, values);
}

/// Local copy so this file does not depend on foundation.
bool listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A number that counts to its new value instead of cutting to it.
///
/// The dashboard's totals refresh once a second off the traffic stream. Drawn as
/// plain text they tick in hard steps, which reads as a stuttering readout
/// rather than a live one. Tweening the underlying integer and formatting each
/// frame keeps the movement continuous.
///
/// [format] is applied to the interpolated value, not the target, so a total
/// crossing a unit boundary rolls through it — `1023 KB` to `1.0 MB` — instead
/// of jumping. Because [Tween.begin] is left null the first build lands on the
/// value directly: a screen opens showing its number, it does not count up from
/// zero.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.duration = Motion.slow,
  });

  final int value;

  /// Renders the tweened value. Call sites that have nothing to show yet return
  /// a placeholder from here and ignore the argument.
  final String Function(int value) format;

  final TextStyle style;

  /// Kept under the one-second refresh cadence, so a tween finishes before the
  /// next sample arrives rather than being retargeted mid-flight.
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: motionOf(context, duration),
      curve: Motion.curve,
      builder: (context, animated, _) => Text(
        format(animated.round()),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// Slides an item from where it used to sit to where it sits now.
///
/// The node list re-sorts under the user — a latency test finishes and the fast
/// nodes rise. Rebuilt in the new order the rows simply teleport, and the one
/// the user was reading is somewhere else with nothing to say it moved. This
/// paints the row at its old position and animates the gap away, so the
/// reordering is something you watch happen.
///
/// It works by measuring rather than by being told an index: after each layout
/// the row records the offset its parent gave it, and a change since the last
/// frame is the animation's distance. That keeps the list a plain [Column] —
/// no fixed row height, no index bookkeeping at the call site.
///
/// The offset comes from [BoxParentData], so it is relative to the parent. A
/// global measurement would count scrolling as movement and every flick of the
/// list would set all the visible rows sliding.
class ReorderSlide extends StatefulWidget {
  const ReorderSlide({super.key, required this.child});

  final Widget child;

  @override
  State<ReorderSlide> createState() => _ReorderSlideState();
}

class _ReorderSlideState extends State<ReorderSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.normal,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Motion.curve,
  );

  /// Where the parent put this row last frame. Null until the first layout,
  /// which is what keeps a freshly built list from animating.
  double? _previousDy;

  /// How far to lift the row at the start of the current animation.
  double _shift = 0;

  /// Furthest a row will be drawn from its resting place, in logical pixels.
  ///
  /// Sorting a long list by latency can move a row most of the list's length. At
  /// that distance the row crosses the whole viewport in 300ms, which reads as a
  /// streak rather than as the row travelling — and on the way it paints over
  /// every row between. Clamping keeps the direction and the arrival, which is
  /// what the movement is there to say, and drops only the part of the journey
  /// nobody can follow. About three rows.
  static const _maxTravel = 240.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Where along the list the parent has put this row.
  ///
  /// Both answers are independent of the current scroll offset: a flex child's
  /// offset is measured inside the flex, and a sliver child's `layoutOffset` is
  /// measured along the sliver's own scroll extent rather than on screen. That
  /// is the property this needs — a figure that moves only when the row's place
  /// in the list moves.
  ///
  /// Render objects in between that merely pass layout through — the
  /// RepaintBoundary a [SliverList] wraps each child in, for one — hold no
  /// position of their own, so the walk climbs past them. An unrecognised layout
  /// returns null and the row simply does not animate.
  double? _positionInList() {
    RenderObject? node = context.findRenderObject();
    for (var hops = 0; node != null && hops < 4; hops++, node = node.parent) {
      final data = node.parentData;
      if (data is SliverMultiBoxAdaptorParentData) return data.layoutOffset;
      if (data is FlexParentData) return data.offset.dy;
    }
    return null;
  }

  void _afterLayout(Duration _) {
    if (!mounted) return;
    final dy = _positionInList();
    if (dy == null) return;
    final previous = _previousDy;
    _previousDy = dy;
    if (previous == null) return;

    final shift = previous - dy;
    // Sub-pixel drift from a reflow that did not actually move the row.
    if (shift.abs() < 0.5) return;
    if (MediaQuery.of(context).disableAnimations) return;

    setState(() => _shift = shift.clamp(-_maxTravel, _maxTravel));
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // Re-armed every build. A reorder rebuilds the whole list, so the frame that
    // moves this row is always a frame it was rebuilt on.
    WidgetsBinding.instance.addPostFrameCallback(_afterLayout);
    return AnimatedBuilder(
      animation: _progress,
      // Paint-only, so the parent still lays the row out in its real slot and
      // the offset read above stays the true one.
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _shift * (1 - _progress.value)),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Rebuilds [builder] when [state] notifies.
///
/// Each page wraps its own body in one of these instead of the shell rebuilding
/// every page on every notification. AppState notifies for everything it owns —
/// a traffic sample a second, a log line per connection — and the shell has no
/// way to tell which page cares, so it redrew four screens nobody was looking at
/// for every line the engine emitted.
///
/// Deliberately not narrowed per page: within a page the notifications that
/// arrive are mostly ones it wants, and a selector per screen is a lot of
/// bookkeeping for the same result. What matters is that the *other* four pages
/// stay still.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.state, required this.builder});

  /// The page's state object, listened to for the lifetime of the page.
  final Listenable state;

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state,
        builder: (context, _) => builder(context),
      );
}
