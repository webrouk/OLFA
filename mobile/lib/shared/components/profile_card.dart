import 'package:flutter/material.dart';

import '../../core/localization/generated/app_localizations.dart';
import '../../core/theme/olfa_colors.dart';
import '../../core/theme/olfa_spacing.dart';
import '../../core/theme/olfa_typography.dart';
import '../../core/widgets/olfa_widgets.dart';
import '../models/models.dart';
import 'labels.dart';
import 'reference_pickers.dart';
import 'verification_ticks.dart';

/// Discovery card: main photo (card-size variant, never the original),
/// name, age, location, verification, short bio, interests and completeness.
class ProfileCard extends StatefulWidget {
  const ProfileCard({super.key, required this.profile, this.likeOpacity = 0, this.passOpacity = 0, this.onOpen});
  final UserProfile profile;
  final double likeOpacity;
  final double passOpacity;
  final VoidCallback? onOpen;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  int _photo = 0;

  @override
  void didUpdateWidget(ProfileCard old) {
    super.didUpdateWidget(old);
    if (old.profile.id != widget.profile.id) _photo = 0;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final p = widget.profile;
    final photos = p.photos;

    return Semantics(
      container: true,
      label: '${p.name}, ${p.age}',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: OlfaColors.white,
          borderRadius: OlfaRadius.all(OlfaRadius.profileCard),
          border: Border.all(color: OlfaColors.gray),
          boxShadow: [BoxShadow(color: OlfaColors.black.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                // Tapping the photo (or anywhere on the card) opens the full profile.
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (p.underReview)
                      const _UnderReviewCover()
                    else
                      OlfaImage(url: photos.isEmpty ? null : photos[_photo].cardUrl),
                    if (photos.length > 1)
                      PositionedDirectional(
                        top: 10,
                        start: 12,
                        end: 12,
                        child: Row(
                          children: [
                            for (var i = 0; i < photos.length; i++)
                              Expanded(
                                child: Container(
                                  height: 3,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: OlfaColors.white.withValues(alpha: i == _photo ? 1 : 0.55),
                                    borderRadius: OlfaRadius.all(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    PositionedDirectional(
                      bottom: 12,
                      end: 12,
                      child: OlfaTag(l.compatibility(p.compatibility), style: OlfaTagStyle.onImage, icon: Icons.people_alt_outlined),
                    ),
                    PositionedDirectional(top: 34, start: 20, child: _Stamp(text: l.like, color: OlfaColors.primary, opacity: widget.likeOpacity, angle: -0.2)),
                    PositionedDirectional(top: 34, end: 20, child: _Stamp(text: l.pass, color: OlfaColors.black, opacity: widget.passOpacity, angle: 0.2)),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: widget.onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text('${p.name}  ${p.age}', style: t.h2, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        VerificationTicks(profile: p, size: 20),
                        const Spacer(),
                        if (p.underReview) OlfaTag(l.newUnderReview, icon: Icons.hourglass_top_rounded),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (p.showLocation)
                      Row(
                        children: [
                          Icon(Icons.place_outlined, size: 14, color: OlfaColors.textMuted),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text('${p.city} · ${occupationLabel(context, p.occupation)}${p.distanceKm != null ? ' · ${p.distanceKm} km' : ''}', style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text(p.bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final k in p.interests.take(3)) OlfaTag(interestLabel(context, k)),
                            ],
                          ),
                        ),
                        Text(l.profileCompleteShort(p.completeness), style: t.caption),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.text, required this.color, required this.opacity, required this.angle});
  final String text;
  final Color color;
  final double opacity;
  final double angle;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: opacity.clamp(0, 1).toDouble(),
      child: Transform.rotate(
        angle: angle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: OlfaColors.white, border: Border.all(color: color, width: 3), borderRadius: OlfaRadius.all(12)),
          child: Text(text, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _UnderReviewCover extends StatelessWidget {
  const _UnderReviewCover();
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ColoredBox(
      color: OlfaColors.gray,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.hourglass_top_rounded, size: 46, color: OlfaColors.primary),
          const SizedBox(height: 10),
          Text(l.newUnderReview, style: context.type.h3),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6), child: Text(l.newUnderReviewBody, textAlign: TextAlign.center, style: context.type.bodySmall)),
        ]),
      ),
    );
  }
}
