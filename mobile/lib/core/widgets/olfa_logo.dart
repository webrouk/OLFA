import 'package:flutter/material.dart';

import '../theme/olfa_colors.dart';

enum OlfaLogoVariant { burgundy, black, symbolOnly }

/// The OLFA symbol: two partners whose bodies form one shared heart.
/// App-icon variants never contain the "OLFA" wordmark.
class OlfaLogo extends StatelessWidget {
  const OlfaLogo({
    super.key,
    this.size = 48,
    this.variant = OlfaLogoVariant.burgundy,
    this.symbolColor = OlfaColors.white,
  });

  final double size;
  final OlfaLogoVariant variant;
  final Color symbolColor;

  @override
  Widget build(BuildContext context) {
    final bg = switch (variant) {
      OlfaLogoVariant.burgundy => OlfaColors.primary,
      OlfaLogoVariant.black => OlfaColors.black,
      OlfaLogoVariant.symbolOnly => null,
    };
    return Semantics(
      label: 'OLFA',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _OlfaSymbolPainter(bg: bg, fg: symbolColor)),
      ),
    );
  }
}

class _OlfaSymbolPainter extends CustomPainter {
  _OlfaSymbolPainter({required this.bg, required this.fg});
  final Color? bg;
  final Color fg;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48; // designed on a 48-unit grid
    if (bg != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(11 * s)),
        Paint()..color = bg!,
      );
    }
    canvas.save();
    canvas.scale(s);
    canvas.translate(0, 1);
    final fill = Paint()..color = fg;
    canvas.drawCircle(const Offset(17.2, 11.4), 3.4, fill);
    canvas.drawCircle(const Offset(30.8, 11.4), 3.4, fill);
    final heart = Path()
      ..moveTo(24, 38.2)
      ..lineTo(13.4, 27.6)
      ..arcToPoint(const Offset(21.9, 19.1), radius: const Radius.circular(6))
      ..lineTo(24, 21.2)
      ..lineTo(26.1, 19.1)
      ..arcToPoint(const Offset(34.6, 27.6), radius: const Radius.circular(6))
      ..close();
    canvas.drawPath(
      heart,
      Paint()
        ..color = fg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OlfaSymbolPainter old) => old.bg != bg || old.fg != fg;
}

/// Full logo lockup: symbol separated from the bilingual wordmark.
class OlfaWordmark extends StatelessWidget {
  const OlfaWordmark({super.key, this.color = OlfaColors.white, this.scale = 1});
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'أُلْفَة',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.w800,
            fontSize: 46 * scale,
            height: 1.1,
            color: color,
          ),
        ),
        SizedBox(height: 6 * scale),
        Text(
          'OLFA',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w600,
            fontSize: 15 * scale,
            letterSpacing: 6.3 * scale,
            color: color.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}
