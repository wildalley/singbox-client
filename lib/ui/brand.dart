/// Shared brand artwork. Decorative images never participate in hit testing.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart_painting.dart';
import 'theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/branding/app-icon.png',
        width: size,
        height: size,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
      );
}

/// In light mode luminance becomes alpha, producing a violet engraving instead
/// of putting a black rectangle behind the controls. Both use the same asset.
///
/// The artwork is not only a bitmap anymore. The image supplies the fine fibre
/// detail, while [_SilkPainter] reshapes and highlights the main ribbons from
/// the live throughput samples. A beat starts for each non-zero reading, so a
/// flowing tunnel keeps the silk alive without a free-running ticker implying
/// traffic when the tunnel is idle.
class SignalArtwork extends StatefulWidget {
  const SignalArtwork({
    super.key,
    this.opacity = 1,
    this.alignment = Alignment.centerRight,
    this.animate = false,
    this.downlink = const [],
    this.uplink = const [],
  });

  final double opacity;
  final Alignment alignment;
  final bool animate;
  final List<int> downlink;
  final List<int> uplink;

  @override
  State<SignalArtwork> createState() => _SignalArtworkState();
}

class _SignalArtworkState extends State<SignalArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  static const _fullScale = 8 * 1024 * 1024;

  static int _rate(SignalArtwork widget) =>
      (widget.downlink.isEmpty ? 0 : widget.downlink.last) +
      (widget.uplink.isEmpty ? 0 : widget.uplink.last);

  double get _intensity {
    final rate = _rate(widget);
    if (rate <= 0) return 0;
    final value = math.log(1 + rate) / math.log(1 + _fullScale);
    return value.clamp(0.0, 1.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SignalArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final canAnimate = widget.animate &&
        _intensity > 0 &&
        !MediaQuery.of(context).disableAnimations &&
        TickerMode.valuesOf(context).enabled;
    if (!canAnimate) {
      _controller.stop();
      return;
    }
    if (!_controller.isAnimating) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.palette;
    final base = Image.asset(
      'assets/branding/signal-flow.webp',
      fit: BoxFit.cover,
      alignment: widget.alignment,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.medium,
    );
    Widget artwork = base;
    if (!dark) {
      artwork = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0,
          0,
          0,
          0,
          86,
          0,
          0,
          0,
          0,
          58,
          0,
          0,
          0,
          0,
          184,
          .2126,
          .7152,
          .0722,
          0,
          0,
        ]),
        child: artwork,
      );
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Opacity(
          opacity: widget.opacity * (dark ? 1 : .45),
          child: ClipRect(
            child: CustomPaint(
              foregroundPainter: _SilkPainter(
                color: dark ? palette.violetSoft : palette.violet,
                dark: dark,
                phase: _controller,
                intensity: _intensity,
              ),
              child: _AnimatedSilkBase(
                animation: _controller,
                child: artwork,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gives the bitmap a restrained whole-ribbon drift underneath the procedural
/// lines. The scale keeps the image covered while it moves, so the animation
/// never exposes a hard edge in the sidebar or clipped hero card.
class _AnimatedSilkBase extends StatelessWidget {
  const _AnimatedSilkBase({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final phase = animation.value * math.pi * 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(
              math.sin(phase) * 5,
              math.cos(phase * 1.13) * 3,
              0,
              1,
            )
            ..scaleByDouble(
              1.025 + math.sin(phase * 1.7) * .004,
              1.025 + math.sin(phase * 1.7) * .004,
              1,
              1,
            ),
          child: child,
        );
      },
    );
  }
}

class _SilkPainter extends CustomPainter {
  _SilkPainter({
    required this.color,
    required this.dark,
    required this.phase,
    required this.intensity,
  }) : super(repaint: phase);

  final Color color;
  final bool dark;
  final Animation<double> phase;
  final double intensity;

  static const _anchors = <Offset>[
    Offset(-.16, .80),
    Offset(.02, .81),
    Offset(.20, .72),
    Offset(.37, .52),
    Offset(.53, .35),
    Offset(.69, .31),
    Offset(.86, .18),
    Offset(1.12, .00),
  ];

  static const _ribbons = <_RibbonSpec>[
    _RibbonSpec(offset: -.046, amplitude: .030, width: 2.0, seed: .4),
    _RibbonSpec(offset: -.014, amplitude: .044, width: 3.2, seed: 1.9),
    _RibbonSpec(offset: .020, amplitude: .050, width: 1.5, seed: 3.4),
    _RibbonSpec(offset: .053, amplitude: .032, width: 2.5, seed: 5.3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 80 || size.height < 80) return;

    final radians = phase.value * math.pi * 2;
    final activity = intensity <= 0 ? 0.0 : .22 + intensity * .78;
    for (final ribbon in _ribbons) {
      final path = _pathFor(ribbon, size, radians, activity);
      final glowAlpha = (dark ? .065 : .050) * activity;
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = ribbon.width * 4.5
          ..color = color.withValues(alpha: glowAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = ribbon.width * (1.1 + intensity * .55)
          ..color = color.withValues(
            alpha: (dark ? .10 : .075) + activity * (dark ? .14 : .11),
          ),
      );

      if (intensity > 0 && ribbon.width >= 2.5) {
        _drawTravelingHighlight(canvas, path, ribbon);
      }
    }
  }

  void _drawTravelingHighlight(
    Canvas canvas,
    Path path,
    _RibbonSpec ribbon,
  ) {
    final metric = path.computeMetrics().firstOrNull;
    if (metric == null || metric.length <= 0) return;

    // A short, feathered segment travels along the actual ribbon path. Split
    // it into pieces so the tail fades smoothly and wrap-around never jumps
    // from the end of a path back to its beginning.
    final length = metric.length * (.12 + intensity * .08);
    final center =
        ((phase.value + ribbon.seed / (math.pi * 2)) % 1) * metric.length;
    const pieces = 9;
    final pieceLength = length / pieces;
    for (var index = 0; index < pieces; index++) {
      final distance = center - length / 2 + (index + .5) * pieceLength;
      var start = distance % metric.length;
      if (start < 0) start += metric.length;
      final end = start + pieceLength;
      final alpha = math.sin((index + 1) / (pieces + 1) * math.pi);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = .8 + intensity * .8
        ..color = Colors.white.withValues(
          alpha: alpha * ((dark ? .16 : .11) + intensity * (dark ? .14 : .10)),
        );
      if (end <= metric.length) {
        canvas.drawPath(metric.extractPath(start, end), paint);
      } else {
        canvas.drawPath(metric.extractPath(start, metric.length), paint);
        canvas.drawPath(metric.extractPath(0, end - metric.length), paint);
      }
    }
  }

  Path _pathFor(
    _RibbonSpec ribbon,
    Size size,
    double radians,
    double activity,
  ) {
    final points = <Offset>[];
    for (var i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      final x = anchor.dx;
      final wave = math.sin(
            radians * .82 + x * 8.8 + ribbon.seed,
          ) *
          ribbon.amplitude *
          activity;
      final secondary = math.cos(
            radians * .61 + x * 14.0 + ribbon.seed * 1.9,
          ) *
          ribbon.amplitude *
          .38 *
          activity;
      final y = anchor.dy + ribbon.offset + wave + secondary;
      points.add(Offset(x * size.width, y * size.height));
    }
    return smoothThrough(
      points,
      minY: -size.height * .3,
      maxY: size.height * 1.3,
    );
  }

  @override
  bool shouldRepaint(covariant _SilkPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dark != dark ||
      oldDelegate.intensity != intensity;
}

class _RibbonSpec {
  const _RibbonSpec({
    required this.offset,
    required this.amplitude,
    required this.width,
    required this.seed,
  });

  final double offset;
  final double amplitude;
  final double width;
  final double seed;
}
