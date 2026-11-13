import 'package:flutter/material.dart';

import '../theme/olfa_colors.dart';
import '../theme/olfa_spacing.dart';
import '../theme/olfa_typography.dart';

/// Primary/secondary button with a consistent height and loading state.
class OlfaButton extends StatelessWidget {
  const OlfaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: OlfaColors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final onTap = loading ? null : onPressed;
    return outlined
        ? OutlinedButton(onPressed: onTap, child: child)
        : FilledButton(onPressed: onTap, child: child);
  }
}

/// Large checkbox row used for consents (terms, age, photo rights).
class OlfaCheck extends StatelessWidget {
  const OlfaCheck({super.key, required this.value, required this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      child: InkWell(
        borderRadius: OlfaRadius.all(8),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: value ? OlfaColors.primary : OlfaColors.white,
                  borderRadius: OlfaRadius.all(7),
                  border: Border.all(
                    color: value ? OlfaColors.primary : OlfaColors.textDisabled,
                    width: 1.5,
                  ),
                ),
                child: value ? const Icon(Icons.check_rounded, size: 16, color: OlfaColors.white) : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: context.type.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable pill (filters, interests, marital status...).
class OlfaChoice extends StatelessWidget {
  const OlfaChoice({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: context.type.bodyMedium.copyWith(
        color: selected ? OlfaColors.primary : OlfaColors.black,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      side: BorderSide(color: selected ? OlfaColors.primary : OlfaColors.gray, width: 1.5),
    );
  }
}

/// "Photos reviewed" badge. Never used to mean identity verification.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle),
      child: Icon(Icons.check_rounded, size: size * 0.66, color: OlfaColors.white),
    );
  }
}

/// Setup flow step indicator (1/4 ... 4/4).
class SetupProgress extends StatelessWidget {
  const SetupProgress({super.key, required this.step, this.total = 4});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: OlfaRadius.all(2),
              child: LinearProgressIndicator(
                value: step / total,
                minHeight: 4,
                color: OlfaColors.primary,
                backgroundColor: OlfaColors.gray,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$step/$total', style: context.type.caption, textDirection: TextDirection.ltr),
        ],
      ),
    );
  }
}

/// Empty / error state with an icon tile, title, body and optional action.
class OlfaEmptyState extends StatelessWidget {
  const OlfaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(28)),
              child: Icon(icon, size: 38, color: OlfaColors.primary),
            ),
            const SizedBox(height: 18),
            Text(title, style: t.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Skeleton block with a gentle opacity pulse (no gradients, per brand rules).
class OlfaSkeleton extends StatefulWidget {
  const OlfaSkeleton({super.key, this.width, this.height = 12, this.radius = 10});
  final double? width;
  final double height;
  final double radius;

  @override
  State<OlfaSkeleton> createState() => _OlfaSkeletonState();
}

class _OlfaSkeletonState extends State<OlfaSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.45).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(widget.radius)),
      ),
    );
  }
}

/// Neutral photo placeholder (silhouette) used until real images load.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: OlfaColors.gray,
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: Alignment.bottomCenter,
          child: Icon(Icons.person_rounded, size: c.biggest.shortestSide * 0.8, color: OlfaColors.black.withValues(alpha: 0.13)),
        ),
      ),
    );
  }
}
