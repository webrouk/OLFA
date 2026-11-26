import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/olfa_colors.dart';
import 'feedback.dart';

/// Neutral silhouette shown when no photo is available.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: OlfaColors.gray,
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: Alignment.bottomCenter,
          child: Icon(Icons.person_rounded, size: c.biggest.shortestSide * 0.85, color: OlfaColors.black.withValues(alpha: 0.13)),
        ),
      ),
    );
  }
}

/// Cached network image with skeleton placeholder, error fallback and a
/// decode size matched to the widget, so full-resolution originals are never
/// decoded into memory for small views.
class OlfaImage extends StatelessWidget {
  const OlfaImage({super.key, required this.url, this.fit = BoxFit.cover, this.blur = false, this.placeholderUrl});
  final String? url;

  /// A smaller, usually already cached variant shown while [url] loads.
  final String? placeholderUrl;
  final BoxFit fit;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final u = url;
    Widget child;
    if (u == null || u.isEmpty) {
      child = const PhotoPlaceholder();
    } else {
      child = LayoutBuilder(
        builder: (context, c) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final w = c.maxWidth.isFinite ? (c.maxWidth * dpr).round() : null;
          return CachedNetworkImage(
            imageUrl: u,
            fit: fit,
            memCacheWidth: w,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => placeholderUrl == null || placeholderUrl == u
                ? const OlfaSkeleton(height: double.infinity, radius: 0)
                : CachedNetworkImage(imageUrl: placeholderUrl!, fit: fit, memCacheWidth: w, fadeInDuration: Duration.zero, placeholder: (_, __) => const OlfaSkeleton(height: double.infinity, radius: 0), errorWidget: (_, __, ___) => const PhotoPlaceholder()),
            errorWidget: (_, __, ___) => const PhotoPlaceholder(),
          );
        },
      );
    }
    if (!blur) return child;
    return ClipRect(
      child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: child),
    );
  }
}

class OlfaAvatar extends StatelessWidget {
  const OlfaAvatar({super.key, this.url, this.size = 48, this.online = false, this.ring = false});
  final String? url;
  final double size;
  final bool online;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final img = ClipOval(child: SizedBox.square(dimension: size, child: OlfaImage(url: url)));
    return SizedBox.square(
      dimension: size + (ring ? 8 : 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (ring)
            Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: OlfaColors.primary, width: 2)),
            ),
          img,
          if (online)
            PositionedDirectional(
              bottom: ring ? 4 : 1,
              end: ring ? 4 : 1,
              child: Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle, border: Border.all(color: OlfaColors.white, width: 2)),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Photos reviewed" badge. Never used to mean identity verification.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 20, this.semanticLabel});
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: size * 0.66, color: OlfaColors.white),
      ),
    );
  }
}
