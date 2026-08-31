/// Shared presentation widgets for the Synapse V4 surfaces.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Rounded card with a subtle border and no heavy shadow.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.accent,
    this.onTap,
    this.glowing = false,
  });

  final Widget child;
  final EdgeInsets padding;

  /// When set, tints the border to signal state (mint connected, amber warning).
  final Color? accent;
  final VoidCallback? onTap;

  /// Adds an outer halo in [accent]. Only for the one panel on a screen that
  /// carries live state — more than one and the glow stops meaning anything.
  final bool glowing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lit = glowing && accent != null;
    final decoration = BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(
        // A glowing edge needs a brighter line under it, or the halo looks
        // detached from the panel it belongs to.
        color: accent?.withValues(alpha: lit ? .45 : .28) ?? palette.border,
      ),
      boxShadow: lit
          ? glow(
              accent!,
              intensity: glowIntensity(Theme.of(context).brightness) * .7,
            )
          : null,
    );

    if (onTap == null) {
      return Container(
        width: double.infinity,
        padding: padding,
        decoration: decoration,
        child: child,
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }
}

/// Section label above a group of panels.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        children: [
          // The reference sheet marks every section with a code-comment sigil
          // (`// DASHBOARD`). It stays a separate text node rather than being
          // folded into [text] so the label still reads as its own string to
          // screen readers and to the widget tests that find it by name.
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(right: Gap.xs),
              child: Text(
                '//',
                style: monoStyle(
                  size: labelStyle?.fontSize ?? 10,
                  weight: FontWeight.w700,
                  color: context.palette.faint,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text.toUpperCase(),
              // Wide tracking is what makes an all-caps label read as a label
              // rather than as shouting; uppercase alone looks cramped.
              style: labelStyle?.copyWith(letterSpacing: 1.4),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Panel header with a leading icon.
class PanelTitle extends StatelessWidget {
  const PanelTitle({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: context.palette.violetSoft),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Scrollable page scaffold with a display-font title.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.onRefresh,
    this.fill = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// Stretches the last child to whatever height the header leaves, instead of
  /// letting it choose its own.
  ///
  /// For a body that is already a scroller — the log pane — where the
  /// alternative is guessing a pixel height that is too short on a desktop
  /// window and leaves dead space under the panel on a phone. Only pass this
  /// when the last child actually wants the room: stretching a short card (an
  /// empty state) to full height looks like a bug, not a layout.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(Gap.xl, 22, Gap.xl, 28);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: Gap.xs),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 26),
      ],
    );

    // Two shapes, because the scroll ownership differs. Normally the page owns
    // the scroll and the children stack up as tall as they like. Filling hands
    // the viewport to one sliver and the last child scrolls inside it, so the
    // page itself stops scrolling and the inner pane takes over.
    final content = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: padding,
          // `children.last` below needs a child to stretch; with none there is
          // nothing to fill either way, so fall through to the plain list.
          sliver: fill && children.isNotEmpty
              ? SliverFillRemaining(
                  // hasScrollBody stays true (the default) because the child
                  // contains a ListView. false measures the child's intrinsic
                  // height, and a viewport refuses to report one — it would have
                  // to build every item, which is the whole point of being lazy.
                  // The framework's own assert says as much. True instead hands
                  // the child the remaining paint extent outright, which is the
                  // measurement wanted here anyway.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      ...children.take(children.length - 1),
                      Expanded(child: children.last),
                    ],
                  ),
                )
              : SliverList.list(children: [header, ...children]),
        ),
      ],
    );

    final centered = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: content,
      ),
    );

    if (onRefresh == null) return centered;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: context.palette.violetSoft,
      backgroundColor: context.palette.surface,
      child: centered,
    );
  }
}

/// Small pill showing a status word with a coloured dot.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Gap.sm : 10,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: tintFill(color),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              // A 7px dot is too small for the full two-layer glow; one tight
              // ring is enough to make it read as lit rather than printed.
              boxShadow: [
                BoxShadow(
                  color: color.withValues(
                    alpha: .55 * glowIntensity(Theme.of(context).brightness),
                  ),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented control used for routing mode and similar small choices.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(Gap.xs),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(value),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.curve,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? palette.violet.withValues(alpha: .22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: value == selected
                          ? palette.violet.withValues(alpha: .55)
                          : Colors.transparent,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      labelOf(value),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: value == selected
                            ? palette.violetSoft
                            : palette.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Settings row: icon, title, subtitle, and either a switch or a chevron.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onChanged,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// When non-null, the row renders a switch.
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Widget? tail = switch ((value, trailing)) {
      (final bool current, _) => Switch(
          value: current,
          onChanged: onChanged,
        ),
      (null, final Widget widget) => widget,
      _ => onTap == null
          ? null
          : Icon(Icons.chevron_right, color: palette.faint, size: 19),
    };

    // Panel paints its own background, so the tile needs a Material of its own
    // for taps to show ink instead of being hidden behind that decoration.
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap ??
            (value != null && onChanged != null
                ? () => onChanged!(!value!)
                : null),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(icon, color: palette.violetSoft, size: 19),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
        trailing: tail,
      ),
    );
  }
}

/// Panel wrapping a list of [SettingRow]s with dividers between them.
class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  const Divider(indent: 52, endIndent: Gap.lg),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

/// Centred empty state with an optional call to action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Panel(
      padding:
          const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.xxl),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: palette.violet.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(icon, color: palette.violetSoft, size: 24),
          ),
          const SizedBox(height: Gap.lg),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[
            const SizedBox(height: Gap.xl),
            action!,
          ],
        ],
      ),
    );
  }
}

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
  );

  final List<int> values;
  final Color color;
  final Color secondColor;
  final Color baselineColor;
  final bool level;

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
        final y = size.height - 1 - (size.height - 1) * i / (_gridLines - 1);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), baseline);
      }
    } else {
      canvas.drawLine(
        Offset(0, size.height - 1),
        Offset(size.width, size.height - 1),
        baseline,
      );
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

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      // Smooth with midpoint control points; a raw polyline looks jittery.
      final previous = points[i - 1];
      final current = points[i];
      final mid = Offset(
          (previous.dx + current.dx) / 2, (previous.dy + current.dy) / 2);
      line.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

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
