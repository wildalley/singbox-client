/// Dashboard components: metric cards, the latency ring, the connections bar
/// chart, and the console background.
///
/// These are the pieces the wide-screen dashboard is built from. They are kept
/// out of `widgets.dart` because that file holds the primitives every page
/// uses, while these only appear on the dashboard.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart_painting.dart';
import 'theme.dart';
import 'widgets.dart' show AnimatedCount;

/// [Panel] with a gradient wash and a lit edge.
///
/// Used for the one card on a screen that should pull the eye first. The wash
/// runs top-left to bottom-right at very low alpha — enough to lift the card
/// off the page background without reading as a coloured surface.
class GlowCard extends StatelessWidget {
  const GlowCard({
    super.key,
    required this.child,
    required this.accent,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.lit = true,
  });

  final Widget child;
  final Color accent;
  final EdgeInsets padding;

  /// When false the card keeps its shape but drops the halo, so a card can go
  /// quiet without the layout shifting.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final intensity = glowIntensity(Theme.of(context).brightness);
    return AnimatedContainer(
      duration: Motion.normal,
      curve: Motion.curve,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: .07), palette.surface),
            palette.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: accent.withValues(alpha: lit ? .40 : .18),
        ),
        boxShadow: lit ? glow(accent, intensity: intensity * .8) : null,
      ),
      child: child,
    );
  }
}

/// One dashboard figure: label, value, and an optional trailing chart.
///
/// The value is monospaced so a column of these keeps its digits aligned while
/// numbers tick over.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    required this.icon,
    required this.accent,
    this.caption,
    this.chart,
  });

  final String label;

  /// The reading itself, as a number so it can be tweened. [format] turns it
  /// into the text that is drawn.
  final int value;

  /// Renders [value]. Cards with nothing to report yet — a rate while
  /// disconnected — return a placeholder from here and ignore the argument.
  final String Function(int value) format;

  /// Secondary line under the value: a rate, a unit, a share.
  final String? caption;
  final IconData icon;
  final Color accent;

  /// Optional visual — a [MiniBars] or a sparkline — pinned under the value.
  final Widget? chart;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(letterSpacing: 1.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          AnimatedCount(
            value: value,
            format: format,
            style: monoStyle(
                size: 22, weight: FontWeight.w600, color: palette.text),
          ),
          if (caption != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(size: 11, color: palette.muted),
            ),
          ],
          if (chart != null) ...[
            // Minimum gap first, then the spacer: these cards sit in an
            // equal-height row, and a card without a caption is shorter by that
            // line. Without the spacer its chart floats mid-card while its
            // neighbours' sit lower, and the row loses its shared baseline. On
            // the tallest card the spacer collapses to zero and the gap holds.
            const SizedBox(height: Gap.md),
            const Spacer(),
            chart!,
          ],
        ],
      ),
    );
  }
}

/// Ring gauge for the selected node's latency.
///
/// The sweep is inverted: a *low* latency fills more of the ring, because the
/// gauge is showing quality, not magnitude. [ceilingMs] is where the ring
/// empties out — anything slower than that reads as a sliver.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.latencyMs,
    required this.label,
    this.size = 132,
    this.ceilingMs = 400,
  });

  /// Null means untested; a negative value means the probe failed.
  final int? latencyMs;

  /// Caption under the reading, e.g. the node's region.
  final String label;
  final double size;
  final int ceilingMs;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final failed = latencyMs != null && latencyMs! < 0;
    final untested = latencyMs == null;
    final colour = failed ? palette.danger : latencyColor(palette, latencyMs);

    // Untested and failed both draw an empty ring; there is no measurement to
    // represent, and a partial ring would imply one.
    final fraction = (untested || failed)
        ? 0.0
        : (1 - (latencyMs! / ceilingMs)).clamp(0.0, 1.0);

    final reading = switch (latencyMs) {
      null => '—',
      final value when value < 0 => '!',
      final value => '$value',
    };

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0, end: fraction),
            duration: Motion.slow,
            curve: Motion.curve,
            builder: (context, value, child) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                fraction: value,
                colour: colour,
                trackColour: palette.surface3,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reading,
                    style: monoStyle(
                      size: 30,
                      weight: FontWeight.w600,
                      color: colour,
                    ),
                  ),
                  if (!untested && !failed)
                    Padding(
                      // Sits on the digits' baseline rather than centred, so
                      // the unit reads as a suffix.
                      padding: const EdgeInsets.only(bottom: 4, left: 2),
                      child: Text('ms',
                          style: monoStyle(size: 11, color: palette.muted)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(letterSpacing: 1.2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.colour,
    required this.trackColour,
  });

  final double fraction;
  final Color colour;
  final Color trackColour;

  /// Leaves a gap at the bottom so the ring reads as a gauge, not a pie.
  static const _startAngle = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect =
        Rect.fromLTWH(0, 0, size.width, size.height).deflate(stroke / 2 + 2);

    final track = Paint()
      ..color = trackColour
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweep, false, track);

    if (fraction <= 0) return;

    canvas.drawArc(
      rect,
      _startAngle,
      _sweep * fraction,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweep,
          colors: [colour.withValues(alpha: .55), colour],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.colour != colour ||
      oldDelegate.trackColour != trackColour;
}

/// Small bar chart for a short series — the connection count over recent ticks.
///
/// Bars rather than a line because the series is a count of discrete things and
/// is short enough that individual samples are worth seeing.
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.color,
    this.height = 28,
    this.barCount = 16,
  });

  final List<int> values;
  final Color color;
  final double height;

  /// Only the most recent [barCount] samples are drawn.
  final int barCount;

  @override
  Widget build(BuildContext context) {
    final recent = values.length <= barCount
        ? values
        : values.sublist(values.length - barCount);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _MiniBarsPainter(
          recent,
          color,
          context.palette.surface3,
          MediaQuery.of(context).devicePixelRatio,
        ),
      ),
    );
  }
}

class _MiniBarsPainter extends CustomPainter {
  _MiniBarsPainter(this.values, this.color, this.emptyColor, this.dpr);

  final List<int> values;
  final Color color;
  final Color emptyColor;

  /// Device pixel ratio, so bar edges are sharp rather than half-shaded. With
  /// twenty-odd bars across a narrow card, every edge landing mid-pixel is what
  /// turns the strip into a grey wash.
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final peak = values.reduce(math.max);
    final slot = size.width / values.length;
    // A third of the slot as spacing keeps the bars distinct at any width.
    final barWidth = math.max(2.0, slot * 0.66);

    for (var i = 0; i < values.length; i++) {
      final ratio = peak <= 0 ? 0.0 : values[i] / peak;
      // Floor at 2px: a zero sample should still show a tick, so gaps in the
      // series don't look like missing data.
      final barHeight = math.max(2.0, ratio * size.height);
      // Both edges snapped, then the width taken from the difference: rounding
      // left and width separately lets a bar come out a pixel wider than its
      // neighbour, and the strip stops looking evenly spaced.
      final left = snapEdge(i * slot + (slot - barWidth) / 2, dpr);
      final right = snapEdge(left + barWidth, dpr);
      final top = snapEdge(size.height - barHeight, dpr);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, right, size.height),
          const Radius.circular(1.5),
        ),
        Paint()
          ..color = ratio <= 0
              ? emptyColor
              : color.withValues(alpha: .35 + ratio * .65),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniBarsPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.dpr != dpr ||
      !_sameValues(oldDelegate.values, values);

  static bool _sameValues(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Programmatic console backdrop: a faint grid under a radial vignette.
///
/// Drawn rather than shipped as a bitmap — see the design note in
/// `docs/design/synapse-v4.md` §3. Alphas are deliberately near the floor of
/// what renders: this should register as texture, not as a visible grid. The
/// optional signal field belongs only on a live connection surface, keeping the
/// rest of the app calm while still giving the dashboard the presence of the
/// reference console.
///
/// The signal field reads the tunnel's own throughput. It used to be a fixed
/// diagram on a twelve-second loop, which meant it kept flowing at a steady rate
/// through an idle tunnel and looked identical during a download — a decoration
/// that implied activity it knew nothing about. Given [downlink] and [uplink] it
/// instead brightens, quickens and stills with the traffic actually moving.
class ConsoleBackground extends StatefulWidget {
  const ConsoleBackground({
    super.key,
    this.child,
    this.accent,
    this.animate = false,
    this.showSignals = false,
    this.downlink = const [],
    this.uplink = const [],
  });

  final Widget? child;

  /// Tint for the vignette and the optional signal field. Defaults to violet.
  final Color? accent;

  /// Whether the signal field should move. It automatically pauses for reduced
  /// motion, while this subtree is not ticker-enabled, and while the samples
  /// below are all zero — an idle tunnel holds still rather than burning a
  /// ticker on motion nobody asked for.
  final bool animate;

  /// Draws the low-contrast node-and-packet field behind a live surface.
  final bool showSignals;

  /// Recent throughput in bytes per second, oldest first.
  ///
  /// The same series [TrafficFlowChart] draws, and normalised the same way, so
  /// the backdrop and the chart in front of it cannot disagree about what a
  /// burst looked like. Empty leaves the field at rest.
  final List<int> downlink;
  final List<int> uplink;

  @override
  State<ConsoleBackground> createState() => _ConsoleBackgroundState();
}

class _ConsoleBackgroundState extends State<ConsoleBackground>
    with SingleTickerProviderStateMixin {
  /// One beat of motion, run once per traffic reading.
  ///
  /// Deliberately not a `repeat()`. A free-running loop would keep the field
  /// moving at a constant rate regardless of the tunnel, which is the dishonesty
  /// this replaces — and it would also never let a frame-settling wait finish, so
  /// every test that renders a connected app would hang instead of failing.
  /// Readings arrive about once a second while connected, so one beat per reading
  /// is continuous motion while traffic flows and stillness the moment it stops.
  ///
  /// A little shorter than the reading interval, so a beat lands and rests rather
  /// than being cut off mid-flight by the next one.
  late final AnimationController _signalController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// How many nodes the field draws, and so how many samples it reads.
  static const _nodeCount = 12;

  /// The rate that lights the field fully, in bytes per second.
  ///
  /// A round 8 MB/s: fast enough that an ordinary download does not peg the
  /// field, slow enough that one is clearly busier than a chat app polling.
  static const _fullScale = 8 * 1024 * 1024;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ConsoleBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  /// Starts a beat if the tunnel is carrying something, and stops otherwise.
  ///
  /// Called on every rebuild, which while connected means once per traffic
  /// reading: each one sets off a beat, and the beats run together into motion
  /// for as long as the readings keep coming. When they stop — or carry nothing —
  /// the last beat finishes and the field comes to rest by itself.
  void _syncAnimation() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final canAnimate = widget.animate &&
        widget.showSignals &&
        // Nothing is moving through the tunnel, so nothing moves here either.
        // The graph stays drawn — it is the tunnel's shape, not its activity.
        _rate(widget) > 0 &&
        !reduceMotion &&
        TickerMode.valuesOf(context).enabled;
    if (!canAnimate) {
      _signalController.stop();
      return;
    }
    // From zero rather than resumed: a beat is one pass of the packets along
    // their links, and restarting it is what makes a new reading visible.
    if (!_signalController.isAnimating) _signalController.forward(from: 0);
  }

  /// The most recent combined throughput sample, in bytes per second.
  static int _rate(ConsoleBackground widget) =>
      (widget.downlink.isEmpty ? 0 : widget.downlink.last) +
      (widget.uplink.isEmpty ? 0 : widget.uplink.last);

  /// Current throughput as a 0..1 brightness, on a log scale.
  ///
  /// Log rather than linear because throughput spans orders of magnitude: on a
  /// linear scale against any ceiling worth having, everything short of a
  /// saturated link would sit indistinguishably at the dim end.
  double get _intensity {
    final rate = _rate(widget);
    if (rate <= 0) return 0;
    final value = math.log(1 + rate) / math.log(1 + _fullScale);
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  /// The recent history as one 0..1 level per node, oldest first.
  ///
  /// Normalised to the peak across both directions, which is exactly how
  /// [TrafficFlowChart] scales the same samples — so the backdrop and the chart
  /// drawn in front of it cannot disagree about how big a burst was.
  List<double> get _levels {
    final down = widget.downlink;
    final up = widget.uplink;
    final length = math.max(down.length, up.length);
    if (length == 0) return List.filled(_nodeCount, 0);

    final combined = <int>[
      for (var i = 0; i < length; i++)
        (i < down.length ? down[i] : 0) + (i < up.length ? up[i] : 0),
    ];
    final peak = combined.fold(0, math.max);
    if (peak <= 0) return List.filled(_nodeCount, 0);

    // Nearest sample rather than an average: a burst is usually one tall
    // sample, and averaging it with its quiet neighbours is how it disappears.
    return [
      for (var i = 0; i < _nodeCount; i++)
        combined[(i * length / _nodeCount).floor()] / peak,
    ];
  }

  @override
  void dispose() {
    _signalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent ?? palette.violet;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ConsolePainter(
          line: palette.text.withValues(alpha: dark ? .014 : .018),
          glowColour: accent.withValues(alpha: dark ? .045 : .025),
          signalColour: accent,
          dark: dark,
          phase: widget.showSignals ? _signalController : null,
          showSignals: widget.showSignals,
          intensity: _intensity,
          levels: _levels,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ConsolePainter extends CustomPainter {
  _ConsolePainter({
    required this.line,
    required this.glowColour,
    required this.signalColour,
    required this.dark,
    required this.phase,
    required this.showSignals,
    required this.intensity,
    required this.levels,
  }) : super(repaint: phase);

  final Color line;
  final Color glowColour;
  final Color signalColour;
  final bool dark;
  final Animation<double>? phase;
  final bool showSignals;

  /// Current throughput, 0..1 on a log scale. Drives brightness and speed.
  final double intensity;

  /// One 0..1 level per node, oldest first — the recent history of the same
  /// samples the traffic chart draws.
  final List<double> levels;

  static const _cell = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = line
      ..strokeWidth = 1;

    for (var x = 0.0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
    }
    for (var y = 0.0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pen);
    }

    // Vignette from the top: pulls attention to the header and fades the grid
    // out before it reaches the content below.
    final centre = Offset(size.width / 2, 0);
    final radius = size.height * 0.9;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          colors: [glowColour, glowColour.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );

    if (showSignals && size.width >= 180 && size.height >= 120) {
      _drawSignalField(canvas, size, phase?.value ?? 0);
    }
  }

  /// A small network diagram, biased to the right side of the card so headings
  /// and controls retain a quiet reading surface.
  ///
  /// The layout is fixed — it stands for the tunnel, which does not change shape
  /// while it is up — but everything drawn over it comes from [levels] and
  /// [intensity]. Each node carries one recent throughput sample: a busy moment
  /// is a bright wide node, a quiet one nearly disappears, and the row of them
  /// left to right is the same history the traffic chart plots. The packets move
  /// at a rate the tunnel is actually sustaining, and an idle tunnel holds
  /// perfectly still.
  void _drawSignalField(Canvas canvas, Size size, double progress) {
    const points = <Offset>[
      Offset(.52, .16),
      Offset(.70, .10),
      Offset(.87, .18),
      Offset(.62, .32),
      Offset(.80, .36),
      Offset(.95, .43),
      Offset(.49, .52),
      Offset(.69, .57),
      Offset(.88, .64),
      Offset(.61, .75),
      Offset(.79, .82),
      Offset(.97, .78),
    ];
    const links = <(int, int)>[
      (0, 1),
      (0, 3),
      (1, 2),
      (1, 4),
      (2, 4),
      (2, 5),
      (3, 4),
      (3, 6),
      (4, 5),
      (4, 7),
      (5, 8),
      (6, 7),
      (6, 9),
      (7, 8),
      (7, 9),
      (7, 10),
      (8, 10),
      (8, 11),
      (9, 10),
      (10, 11),
    ];

    /// The sample at [index], or 0 where there is no history for it yet.
    double level(int index) {
      if (index < 0 || index >= levels.length) return 0;
      final value = levels[index];
      return value < 0 ? 0 : (value > 1 ? 1 : value);
    }

    Offset pointAt(int index) {
      final source = points[index];
      final angle = progress * math.pi * 2 + index * 1.73;
      // Sub-pixel drift is enough to keep the field alive. Larger motion makes
      // a dense dashboard feel unstable, especially beside changing figures.
      // Busy nodes drift furthest, so the eye finds the active part of the
      // history without the whole field becoming restless.
      final reach = 1.1 + level(index) * 2.2;
      return Offset(
        source.dx * size.width + math.sin(angle) * reach,
        source.dy * size.height + math.cos(angle * 1.17) * reach * .88,
      );
    }

    final resolved = <Offset>[
      for (var i = 0; i < points.length; i++) pointAt(i)
    ];

    // The graph is always drawn: it stands for the tunnel, which is up whether
    // or not bytes are moving right now. Its links only brighten with the two
    // samples they join, so an idle tunnel is a faint outline rather than a
    // missing one.
    final baseLink = dark ? .055 : .032;
    final litLink = dark ? .105 : .065;
    for (final (from, to) in links) {
      final share = (level(from) + level(to)) / 2;
      canvas.drawLine(
        resolved[from],
        resolved[to],
        Paint()
          ..color = signalColour.withValues(
            alpha: baseLink + (litLink - baseLink) * share,
          )
          ..strokeWidth = 1,
      );
    }

    for (var i = 0; i < resolved.length; i++) {
      final share = level(i);
      final haloAlpha = (dark ? .07 : .04) + (dark ? .16 : .09) * share;
      final nodeAlpha = (dark ? .26 : .18) + (dark ? .40 : .28) * share;
      canvas.drawCircle(
        resolved[i],
        2.6 + share * 2.4,
        Paint()
          ..color = signalColour.withValues(alpha: haloAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        resolved[i],
        1.1 + share * .9,
        Paint()..color = signalColour.withValues(alpha: nodeAlpha),
      );
    }

    // Packets are the part that has to be honest: a moving dot reads as traffic,
    // so their number and speed come from the throughput rather than from a
    // fixed loop. Nothing moving means none drawn — the caller has stopped the
    // ticker by then, so this is what an idle tunnel actually looks like.
    if (intensity <= 0) return;

    const packetLinks = <(int, int)>[(0, 4), (3, 7), (6, 10), (4, 8)];
    final count = 1 + (intensity * (packetLinks.length - 1)).round();
    // Traversals per beat, so throughput sets the speed: a busy tunnel sends a
    // packet along its link six times where an idle-but-open one sends it once.
    //
    // A whole number, which is what makes consecutive beats seam. Each beat runs
    // progress 0 to 1, so a fractional count would leave the packets somewhere
    // mid-link at the end of one and snap them back to the start of the next.
    final turns = 1 + (intensity * 5).round();
    final packetHalo = Paint()
      ..color = signalColour.withValues(alpha: dark ? .42 : .24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final packet = Paint()
      ..color = signalColour.withValues(alpha: dark ? .9 : .72);
    for (var i = 0; i < count; i++) {
      final (from, to) = packetLinks[i];
      final travel = (progress * turns + i * .27) % 1;
      final eased = Curves.easeInOut.transform(travel);
      final position = Offset.lerp(resolved[from], resolved[to], eased)!;
      canvas.drawCircle(position, 4.6, packetHalo);
      canvas.drawCircle(position, 1.8, packet);
    }
  }

  @override
  bool shouldRepaint(covariant _ConsolePainter oldDelegate) =>
      oldDelegate.line != line ||
      oldDelegate.glowColour != glowColour ||
      oldDelegate.signalColour != signalColour ||
      oldDelegate.dark != dark ||
      oldDelegate.showSignals != showSignals ||
      // A new traffic sample has to reach the canvas even while the ticker is
      // stopped: an idle field that just took one reading is not repainted by
      // `repaint: phase` alone, and would keep showing the old history.
      oldDelegate.intensity != intensity ||
      !_sameLevels(oldDelegate.levels, levels);

  static bool _sameLevels(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The wide dashboard's centrepiece: down and up rates on one shared scale.
///
/// Both series share a peak so the two curves stay comparable — scaling each to
/// its own maximum would make a trickle of upload look like a flood. Sized for
/// the full panel width rather than the sparkline's inline strip.
class TrafficFlowChart extends StatelessWidget {
  const TrafficFlowChart({
    super.key,
    required this.downlink,
    required this.uplink,
    required this.downColor,
    required this.upColor,
    this.height = 168,
  });

  final List<int> downlink;
  final List<int> uplink;
  final Color downColor;
  final Color upColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _FlowPainter(
          downlink: downlink,
          uplink: uplink,
          downColor: downColor,
          upColor: upColor,
          gridColor: palette.border,
          dpr: MediaQuery.of(context).devicePixelRatio,
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.downlink,
    required this.uplink,
    required this.downColor,
    required this.upColor,
    required this.gridColor,
    required this.dpr,
  });

  final List<int> downlink;
  final List<int> uplink;
  final Color downColor;
  final Color upColor;
  final Color gridColor;

  /// Device pixel ratio, so the rules land on whole pixels. A painter cannot
  /// read it itself.
  final double dpr;

  /// Horizontal rules, including the baseline. Four is enough to read height off
  /// without turning the panel into graph paper.
  static const _gridLines = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < _gridLines; i++) {
      final span = size.height - 1;
      final y = crispLine(span - span * i / (_gridLines - 1), dpr);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // One shared peak across both series, so the curves stay comparable.
    final peak = [...downlink, ...uplink].fold(0, math.max);
    if (peak <= 0) return;

    // Upload drawn first: it is usually the smaller series, so leaving it on top
    // would let its fill wash over the download curve.
    _series(canvas, size, uplink, peak, upColor);
    _series(canvas, size, downlink, peak, downColor);
  }

  void _series(
    Canvas canvas,
    Size size,
    List<int> values,
    int peak,
    Color color,
  ) {
    if (values.length < 2) return;

    final step = size.width / (values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(i * step, size.height - (values[i] / peak) * (size.height - 6)),
    ];

    // Through every sample — see [smoothThrough]. The old midpoint smoothing
    // drew a burst at about half its height, on the one chart whose job is to
    // show bursts.
    final line = smoothThrough(points, minY: 1, maxY: size.height - 1);

    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: .22),
            color.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowPainter oldDelegate) =>
      oldDelegate.downColor != downColor ||
      oldDelegate.upColor != upColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.dpr != dpr ||
      !_MiniBarsPainter._sameValues(oldDelegate.downlink, downlink) ||
      !_MiniBarsPainter._sameValues(oldDelegate.uplink, uplink);
}
