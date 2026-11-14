import 'package:flutter/material.dart';

import '../theme/olfa_colors.dart';
import '../theme/olfa_spacing.dart';
import 'motion.dart';

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({required this.label, required this.loading, required this.icon, required this.spinner});
  final String label;
  final bool loading;
  final IconData? icon;
  final Color spinner;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: spinner));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1)),
      ],
    );
  }
}

/// Filled burgundy button. `loading` disables it to prevent double submission.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon, this.expand = true, this.inverted = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;
  final bool inverted; // white button on burgundy surfaces

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: Size(expand ? double.infinity : 0, OlfaSize.buttonHeight),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      backgroundColor: inverted ? OlfaColors.white : null,
      foregroundColor: inverted ? OlfaColors.primary : null,
    );
    return PressScale(
      enabled: onPressed != null && !loading,
      child: FilledButton(
        style: style,
        onPressed: loading ? null : onPressed,
        child: _ButtonContent(label: label, loading: loading, icon: icon, spinner: inverted ? OlfaColors.primary : OlfaColors.white),
      ),
    );
  }
}

/// Outlined neutral button for secondary actions.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      enabled: onPressed != null && !loading,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: Size(expand ? double.infinity : 0, OlfaSize.buttonHeight), padding: const EdgeInsets.symmetric(horizontal: 18)),
        onPressed: loading ? null : onPressed,
        child: _ButtonContent(label: label, loading: loading, icon: icon, spinner: OlfaColors.primary),
      ),
    );
  }
}

enum OlfaIconStyle { plain, soft, elevated, filled }

/// 44×44 minimum tap target, consistent radius, semantic label required.
class OlfaIconButton extends StatelessWidget {
  const OlfaIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.style = OlfaIconStyle.plain,
    this.size = 44,
    this.circle = false,
    this.iconSize,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final OlfaIconStyle style;
  final double size;
  final bool circle;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (style) {
      OlfaIconStyle.plain => (Colors.transparent, OlfaColors.black, null),
      OlfaIconStyle.soft => (OlfaColors.gray, OlfaColors.black, null),
      OlfaIconStyle.elevated => (OlfaColors.white, OlfaColors.black, const BorderSide(color: OlfaColors.gray)),
      OlfaIconStyle.filled => (OlfaColors.primary, OlfaColors.white, null),
    };
    final shape = circle
        ? CircleBorder(side: border ?? BorderSide.none)
        : RoundedRectangleBorder(borderRadius: OlfaRadius.all(14), side: border ?? BorderSide.none);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        child: Opacity(
          opacity: onPressed == null ? 0.35 : 1,
          child: PressScale(
            enabled: onPressed != null,
            child: Material(
              color: bg,
              shape: shape,
              child: InkWell(
                customBorder: shape,
                onTap: onPressed,
                child: SizedBox.square(dimension: size, child: Icon(icon, size: iconSize ?? size * 0.48, color: fg)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
