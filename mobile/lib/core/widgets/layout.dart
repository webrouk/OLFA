import 'package:flutter/material.dart';

import '../theme/olfa_colors.dart';
import '../theme/olfa_spacing.dart';
import '../theme/olfa_typography.dart';

/// Caps content width on tablets / landscape so lines stay readable.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.max = 560});
  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}

/// Scrollable form with a pinned bottom action that rises with the keyboard.
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.children, this.action, this.header, this.title, this.actions});
  final List<Widget> children;
  final Widget? action;
  final Widget? header;
  final String? title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: title == null ? null : Text(title!), actions: actions),
      body: SafeArea(
        top: false,
        child: ContentWidth(
          child: Column(
            children: [
              if (header != null) header!,
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                ),
              ),
              if (action != null)
                DecoratedBox(
                  decoration: const BoxDecoration(color: OlfaColors.white, border: Border(top: BorderSide(color: OlfaColors.gray))),
                  child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 16), child: action),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.body});
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.h1),
          if (body != null) ...[const SizedBox(height: 8), Text(body!, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted))],
        ],
      ),
    );
  }
}

class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.step, this.total = 4});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Semantics(
        label: '$step / $total',
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: OlfaRadius.all(2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: step / total),
                  duration: const Duration(milliseconds: 300),
                  builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 4, color: OlfaColors.primary, backgroundColor: OlfaColors.gray),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('$step/$total', style: context.type.caption, textDirection: TextDirection.ltr),
          ],
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.top = 26});
  final String text;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.only(top: top, bottom: 10, start: 4, end: 4),
        child: Row(
          children: [
            Expanded(child: Text(text, style: context.type.bodySmall.copyWith(fontWeight: FontWeight.w600, color: OlfaColors.textMuted))),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Rounded group container for list tiles / content blocks.
class OlfaCard extends StatelessWidget {
  const OlfaCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.color = OlfaColors.white, this.borderColor = OlfaColors.gray});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: OlfaRadius.all(OlfaRadius.card), border: Border.all(color: borderColor)),
        child: child,
      );
}

class OlfaListTile extends StatelessWidget {
  const OlfaListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.accent = false,
    this.danger = false,
    this.showChevron = true,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool accent;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final hl = accent || danger;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: hl ? OlfaColors.primaryTint() : OlfaColors.gray, borderRadius: OlfaRadius.all(12)),
                child: Icon(icon, size: 20, color: hl ? OlfaColors.primary : OlfaColors.black),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w500, color: danger ? OlfaColors.primary : null)),
                    if (subtitle != null) Text(subtitle!, style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (trailing == null && showChevron && onTap != null)
                Icon(Icons.chevron_right_rounded, color: OlfaColors.textDisabled) // mirrors in RTL,
            ],
          ),
        ),
      ),
    );
  }
}

/// Column of tiles separated by hairlines inside an [OlfaCard].
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => OlfaCard(
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(), children[i]],
          ],
        ),
      );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.icon = Icons.info_outline_rounded, this.accent = false, this.trailing});
  final String text;
  final IconData icon;
  final bool accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: accent ? OlfaColors.primaryTint() : OlfaColors.gray, borderRadius: OlfaRadius.all(16)),
        child: Row(
          crossAxisAlignment: trailing == null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: OlfaColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: context.type.bodySmall)),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      );
}

/// Small rounded label (plan name, status...).
class OlfaTag extends StatelessWidget {
  const OlfaTag(this.text, {super.key, this.style = OlfaTagStyle.neutral, this.icon});
  final String text;
  final OlfaTagStyle style;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (style) {
      OlfaTagStyle.neutral => (OlfaColors.gray, OlfaColors.black),
      OlfaTagStyle.accent => (OlfaColors.primaryTint(), OlfaColors.primary),
      OlfaTagStyle.dark => (OlfaColors.black, OlfaColors.white),
      OlfaTagStyle.primary => (OlfaColors.primary, OlfaColors.white),
      OlfaTagStyle.onImage => (OlfaColors.white, OlfaColors.black),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: OlfaRadius.all(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg, fontFamily: DefaultTextStyle.of(context).style.fontFamily)),
        ],
      ),
    );
  }
}

enum OlfaTagStyle { neutral, accent, dark, primary, onImage }

/// Keeps every page readable on tablets and wide windows: up to
/// [OlfaBreakpoints.readable] wide, centred on the grey surface. Phones are
/// unaffected (the page fills the screen as before).
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth <= OlfaBreakpoints.readable + 40) return child;
      return ColoredBox(
        color: OlfaColors.gray,
        child: Center(
          child: SizedBox(
            width: OlfaBreakpoints.readable,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: OlfaColors.white, border: BorderDirectional(start: BorderSide(color: OlfaColors.gray), end: BorderSide(color: OlfaColors.gray))),
              child: ClipRect(child: child),
            ),
          ),
        ),
      );
    });
  }
}
