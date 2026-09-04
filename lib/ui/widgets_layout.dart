part of 'widgets.dart';

/// Rounded card with a subtle border and no heavy shadow.
///
/// Tappable panels share one hover, press, and selected treatment. That keeps
/// the controls in nodes, subscriptions, and other dashboard surfaces feeling
/// related while avoiding any layout-changing hover effects.
class Panel extends StatefulWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.accent,
    this.onTap,
    this.glowing = false,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsets padding;

  /// When set, tints the border to signal state (mint connected, amber warning).
  final Color? accent;
  final VoidCallback? onTap;

  /// Adds an outer halo in [accent]. Only for the one panel on a screen that
  /// carries live state — more than one and the glow stops meaning anything.
  final bool glowing;

  /// Applies a tinted fill and a stronger edge to a selected, tappable item.
  final bool selected;

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final interactive = widget.onTap != null;
    final accent = widget.accent ?? palette.violet;
    final lit = widget.glowing && widget.accent != null;
    final elevated = interactive && (_hovered || _pressed);

    var fill = widget.selected
        ? Color.alphaBlend(accent.withValues(alpha: .10), palette.surface)
        : palette.surface;
    if (elevated) {
      fill = Color.alphaBlend(
        accent.withValues(alpha: _pressed ? .095 : .045),
        fill,
      );
    }

    final borderColor = widget.selected
        ? accent.withValues(alpha: .65)
        : elevated
            ? accent.withValues(alpha: .38)
            : widget.accent?.withValues(alpha: lit ? .45 : .28) ??
                palette.border;
    final decoration = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: borderColor),
      boxShadow: [
        if (lit)
          ...glow(
            widget.accent!,
            intensity: glowIntensity(Theme.of(context).brightness) * .7,
          ),
        if (elevated)
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? (_pressed ? .14 : .09)
                  : (_pressed ? .07 : .035),
            ),
            blurRadius: _pressed ? 8 : 14,
            offset: Offset(0, _pressed ? 2 : 5),
          ),
      ],
    );

    if (!interactive) {
      return Container(
        width: double.infinity,
        padding: widget.padding,
        decoration: decoration,
        child: widget.child,
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) {
          if (_hovered != value && mounted) setState(() => _hovered = value);
        },
        onHighlightChanged: (value) {
          if (_pressed != value && mounted) setState(() => _pressed = value);
        },
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedScale(
          scale: _pressed ? .992 : 1,
          duration: Motion.fast,
          curve: Motion.curve,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            width: double.infinity,
            padding: widget.padding,
            decoration: decoration,
            child: widget.child,
          ),
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

    // Two shapes, because the scroll ownership differs.
    //
    // Normally the page owns the scroll and the children stack up as tall as
    // they like, header included.
    //
    // Filling is the other way round: the last child is already a scroller, so
    // it takes the room the header leaves and the page itself does not scroll at
    // all. The header sits *outside* any viewport there — it is chrome, and a
    // title that scrolls away from the pane it labels is a title in the wrong
    // place.
    //
    // This used to be a CustomScrollView with a SliverFillRemaining in both
    // cases, which put the header inside the scrollable even when filling. The
    // sliver was sized to the viewport while SliverPadding added 50px on top of
    // it, so the outer view had exactly that much scroll — just enough to drag
    // the title out of sight above a log pane that was doing its own scrolling
    // underneath. Two nested scrollables, and the wrong one moved.
    final Widget content;
    if (fill && children.isNotEmpty) {
      content = Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            ...children.take(children.length - 1),
            Expanded(child: children.last),
          ],
        ),
      );
    } else {
      content = CustomScrollView(
        slivers: [
          SliverPadding(
            padding: padding,
            sliver: SliverList.list(children: [header, ...children]),
          ),
        ],
      );
    }

    final centered = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: content,
      ),
    );

    // A RefreshIndicator needs a scrollable of its own to drive it, and in the
    // filling shape the page has none — the scroller belongs to the last child.
    // No caller combines the two today; the assert says so rather than leaving a
    // pull-to-refresh that silently never fires.
    assert(
      onRefresh == null || !fill,
      'PageFrame cannot combine onRefresh with fill: the filling shape has no '
      'scrollable of its own for the indicator to follow',
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
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.curve,
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
///
/// One indicator slides between the segments rather than each segment fading its
/// own fill in and out. Two fills cross-fading reads as two things blinking; one
/// moving reads as the selection travelling, which is what happened.
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

  /// Edge on the indicator, and the inset it costs the labels.
  ///
  /// The labels carry it too. The indicator is a layer of its own now, so it no
  /// longer contributes its edge to the track's height the way a border on each
  /// segment did — without this the control loses those two pixels and every
  /// row below it on the page moves up.
  static const _edge = 1.0;

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
      child: Stack(
        children: [
          // Positioned, so it does not size the stack — the row below does, and
          // painting first puts the indicator behind the labels.
          Positioned.fill(
            child: AnimatedAlign(
              alignment: _indicatorAlignment,
              duration: motionOf(context, Motion.normal),
              curve: Motion.curve,
              child: FractionallySizedBox(
                widthFactor: 1 / values.length,
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.violet.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: palette.violet.withValues(alpha: .55),
                      width: _edge,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final value in values)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(value),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedDefaultTextStyle(
                      duration: motionOf(context, Motion.normal),
                      curve: Motion.curve,
                      // Merged onto the ambient style rather than given whole.
                      // AnimatedDefaultTextStyle *replaces* the default for its
                      // subtree, where a style handed to a Text merges into it —
                      // so stating only the differences here is what keeps the
                      // body family, the CJK fallback, and the 1.4 line height
                      // that sets this control's height.
                      style: DefaultTextStyle.of(context).style.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: value == selected
                                ? palette.violetSoft
                                : palette.muted,
                          ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10 + _edge,
                        ),
                        child: Center(child: Text(labelOf(value))),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Centre of the selected segment, in the [-1, 1] the alignment uses.
  ///
  /// A segment's centre sits half a segment in from its edge, so the usable
  /// travel is the track minus one segment — mapping the index across that is
  /// what keeps the indicator concentric with its label at both ends.
  Alignment get _indicatorAlignment {
    if (values.length < 2) return Alignment.center;
    final index = values.indexOf(selected);
    if (index < 0) return Alignment.center;
    return Alignment(-1 + 2 * index / (values.length - 1), 0);
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
