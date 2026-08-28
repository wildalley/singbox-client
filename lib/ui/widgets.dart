/// Shared presentation widgets for the Obsidian Signal surfaces.
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
  });

  final Widget child;
  final EdgeInsets padding;

  /// When set, tints the border to signal state (mint connected, amber warning).
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final decoration = BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
        color: accent?.withValues(alpha: .28) ?? palette.border,
      ),
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
        borderRadius: BorderRadius.circular(15),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
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
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final content = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.xl, 22, Gap.xl, 28),
          sliver: SliverList.list(
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
              ...children,
            ],
          ),
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
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
        borderRadius: BorderRadius.circular(11),
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
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? palette.violet.withValues(alpha: .22)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
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
        const SizedBox(height: 22),
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
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.xxl),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: palette.violet.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(15),
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
    this.height = 62,
  });

  final List<int> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        // A painter has no BuildContext, so the baseline colour is passed in.
        painter: _SparklinePainter(values, color, context.palette.border),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color, this.baselineColor);

  final List<int> values;
  final Color color;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Baseline so an idle tunnel still reads as a chart rather than blank space.
    final baseline = Paint()
      ..color = baselineColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      baseline,
    );

    if (values.length < 2) return;

    final peak = values.reduce((a, b) => a > b ? a : b);
    if (peak <= 0) return;

    final step = size.width / (values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(i * step, size.height - (values[i] / peak) * (size.height - 4)),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      // Smooth with midpoint control points; a raw polyline looks jittery.
      final previous = points[i - 1];
      final current = points[i];
      final mid = Offset((previous.dx + current.dx) / 2, (previous.dy + current.dy) / 2);
      line.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .26), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.baselineColor != baselineColor ||
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
