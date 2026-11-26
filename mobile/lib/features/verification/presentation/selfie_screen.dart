import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/network/api_client.dart' show useApi;
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../profile/application/profile_controllers.dart';
import '../../profile/presentation/setup_screens.dart' show setupTotal;
import '../data/selfie_analyzer.dart';
import '../data/selfie_repository.dart';
import '../domain/selfie_criteria.dart';

/// Sign-up step right after the profile photos: a live selfie showing a random
/// gesture. Checked on the phone (face detection), then by the server, then by
/// the verification team, who compare it with the profile photos.
///
/// [retake]: the team asked for a new selfie — no profile resubmission needed here
/// (the server sends the profile back to review with the new selfie).
class SelfieScreen extends ConsumerStatefulWidget {
  const SelfieScreen({super.key, this.retake = false});
  final bool retake;
  @override
  ConsumerState<SelfieScreen> createState() => _SelfieScreenState();
}

enum _Stage { intro, gesture, checking, result, sending }

class _SelfieScreenState extends ConsumerState<SelfieScreen> {
  _Stage _stage = _Stage.intro;
  bool _femaleReviewer = false;
  SelfieChallenge? _challenge;
  Uint8List? _jpeg;
  DeviceChecks? _checks;
  List<String> _failed = const [];
  bool _challengeUsed = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _challenge != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _expired => _challenge == null || _challenge!.expiresAt.isBefore(DateTime.now());

  Future<void> _newChallenge() async {
    try {
      final c = await ref.read(selfieRepositoryProvider).challenge();
      if (!mounted) return;
      setState(() {
        _challenge = c;
        _challengeUsed = false;
        _stage = _Stage.gesture;
      });
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    }
  }

  /// Front camera only — no gallery, so an old photo cannot be used (criterion "live").
  Future<void> _capture() async {
    if (_expired || _challengeUsed) return _newChallenge();
    final x = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 2000, imageQuality: 95);
    if (x == null || !mounted) return;
    setState(() => _stage = _Stage.checking);
    final analyzer = SelfieAnalyzer();
    try {
      final dir = await getTemporaryDirectory();
      final target = '${dir.path}/olfa_selfie_${DateTime.now().microsecondsSinceEpoch}.jpg';
      // JPEG, long side ≤ 1600 px, location / device metadata removed on the phone
      final out = await FlutterImageCompress.compressAndGetFile(x.path, target, minWidth: 1600, minHeight: 1600, quality: 90, keepExif: false, format: CompressFormat.jpeg);
      final path = out?.path ?? x.path;
      final bytes = await File(path).readAsBytes();
      final checks = await analyzer.analyze(path, bytes);
      await analyzer.discard(x.path);
      if (path != x.path) await analyzer.discard(path);
      if (!mounted) return;
      setState(() {
        _jpeg = bytes;
        _checks = checks;
        _failed = [for (final f in failedDeviceChecks(checks)) f.name];
        _stage = _Stage.result;
      });
    } catch (e) {
      await analyzer.discard(x.path);
      if (mounted) {
        setState(() => _stage = _Stage.gesture);
        showToast(context, AppLocalizations.of(context).selfieAnalyzeError);
      }
    }
  }

  Future<void> _send() async {
    final c = _challenge, jpeg = _jpeg, checks = _checks;
    if (c == null || jpeg == null || checks == null) return;
    setState(() => _stage = _Stage.sending);
    try {
      await ref.read(selfieRepositoryProvider).submit(c, jpeg, checks, preferFemaleReviewer: _femaleReviewer);
      _jpeg = null; // nothing kept on the phone
      if (!widget.retake) {
        final d = ref.read(profileDraftProvider);
        if (d.accountType?.isProfessional ?? false) {
          await ref.read(profileDraftProvider.notifier).submitProfessionalPhotos();
        } else {
          await ref.read(profileDraftProvider.notifier).submit();
        }
      }
      ref.invalidate(verificationProvider);
      if (mounted) context.go(Routes.verification);
    } on SelfieChecksFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = e.failed;
        _challengeUsed = true; // the server used this capture: the next one gets a new gesture
        _stage = _Stage.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _Stage.result);
      showToast(context, failureMessage(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = ref.watch(profileDraftProvider);
    final total = setupTotal(d);
    return switch (_stage) {
      _Stage.intro => FormPage(
          header: widget.retake ? null : SetupProgress(step: total, total: total),
          action: PrimaryButton(label: l.selfieStart, icon: Icons.photo_camera_front_rounded, onPressed: _newChallenge),
          children: [
            PageHeading(l.selfieTitle, body: l.selfieBody),
            _CriteriaList(),
            const SizedBox(height: 14),
            InfoBanner(text: l.selfiePrivacy, icon: Icons.lock_outline_rounded, accent: true),
            const SizedBox(height: 10),
            OlfaCard(
              child: SwitchListTile.adaptive(
                value: _femaleReviewer,
                onChanged: (v) => setState(() => _femaleReviewer = v),
                title: Text(l.selfieFemaleReviewer, style: context.type.bodyMedium),
                subtitle: Text(l.selfieFemaleReviewerHint, style: context.type.caption),
              ),
            ),
          ],
        ),
      _Stage.gesture => FormPage(
          header: widget.retake ? null : SetupProgress(step: total, total: total),
          action: PrimaryButton(label: l.selfieOpenCamera, icon: Icons.photo_camera_front_rounded, onPressed: _capture),
          children: [
            PageHeading(l.selfieGestureTitle, body: l.selfieGestureBody),
            _GestureCard(gesture: _challenge!.gesture),
            const SizedBox(height: 14),
            if (!_expired)
              Text(l.selfieExpiresIn('${_challenge!.expiresAt.difference(DateTime.now()).inMinutes + 1}'), style: context.type.caption, textAlign: TextAlign.center)
            else
              Text(l.selfieExpired, style: context.type.caption.copyWith(color: OlfaColors.primary), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            for (final tip in [l.selfieTipLight, l.selfieTipFace, l.selfieTipAlone]) _Bullet(tip),
          ],
        ),
      _Stage.checking || _Stage.sending => Scaffold(
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox.square(dimension: 34, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 16),
              Text(_stage == _Stage.checking ? l.selfieChecking : l.selfieSending, style: context.type.bodyMedium),
            ]),
          ),
        ),
      _Stage.result => FormPage(
          header: widget.retake ? null : SetupProgress(step: total, total: total),
          action: _failed.isEmpty
              ? PrimaryButton(label: l.selfieSend, icon: Icons.verified_user_outlined, onPressed: _send)
              : PrimaryButton(label: l.selfieRetake, icon: Icons.refresh_rounded, onPressed: _capture),
          children: [
            PageHeading(_failed.isEmpty ? l.selfiePassedTitle : l.selfieFailedTitle, body: _failed.isEmpty ? l.selfiePassedBody : l.selfieFailedBody),
            if (_jpeg != null)
              Center(
                child: ClipRRect(
                  borderRadius: OlfaRadius.all(24),
                  child: SizedBox(width: 180, height: 240, child: Image.memory(_jpeg!, fit: BoxFit.cover, gaplessPlayback: true)),
                ),
              ),
            const SizedBox(height: 16),
            OlfaCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                for (final c in SelfieCriterion.values)
                  _CheckRow(criterion: c, state: _failed.contains(c.name) ? false : (c.checkedOnDevice || c == SelfieCriterion.live ? true : null)),
              ]),
            ),
            if (_failed.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final f in _failed) _Bullet(criterionFix(l, SelfieCriterion.fromApi(f) ?? SelfieCriterion.quality)),
            ],
            if (_failed.isEmpty && !useApi) ...[const SizedBox(height: 10), InfoBanner(text: l.selfieDemoNote)],
          ],
        ),
    };
  }
}

String criterionTitle(AppLocalizations l, SelfieCriterion c) => switch (c) {
      SelfieCriterion.live => l.critLive,
      SelfieCriterion.oneFace => l.critOneFace,
      SelfieCriterion.visible => l.critVisible,
      SelfieCriterion.straight => l.critStraight,
      SelfieCriterion.quality => l.critQuality,
      SelfieCriterion.gesture => l.critGesture,
      SelfieCriterion.samePerson => l.critSamePerson,
      SelfieCriterion.real => l.critReal,
    };

String criterionFix(AppLocalizations l, SelfieCriterion c) => switch (c) {
      SelfieCriterion.live => l.fixLive,
      SelfieCriterion.oneFace => l.fixOneFace,
      SelfieCriterion.visible => l.fixVisible,
      SelfieCriterion.straight => l.fixStraight,
      SelfieCriterion.quality => l.fixQuality,
      SelfieCriterion.gesture => l.fixGesture,
      SelfieCriterion.samePerson => l.fixSamePerson,
      SelfieCriterion.real => l.fixReal,
    };

String gestureLabel(AppLocalizations l, SelfieGesture g) => switch (g) {
      SelfieGesture.thumbUp => l.gestureThumbUp,
      SelfieGesture.victory => l.gestureVictory,
      SelfieGesture.openPalm => l.gestureOpenPalm,
      SelfieGesture.pointUp => l.gesturePointUp,
      SelfieGesture.handOnChin => l.gestureHandOnChin,
    };

class _CriteriaList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OlfaCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        for (final c in SelfieCriterion.values) _CheckRow(criterion: c, state: null, showWho: true),
      ]),
    ).withLabel(l.selfieCriteriaTitle, context);
  }
}

extension on Widget {
  Widget withLabel(String label, BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8), child: Text(label, style: context.type.inputLabel)),
        this,
      ]);
}

/// [state]: true passed · false failed · null not checked yet / checked by the team.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.criterion, required this.state, this.showWho = false});
  final SelfieCriterion criterion;
  final bool? state;
  final bool showWho;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (icon, color) = switch (state) {
      true => (Icons.check_circle_rounded, OlfaColors.primary),
      false => (Icons.cancel_rounded, OlfaColors.primary),
      null => (Icons.radio_button_unchecked_rounded, OlfaColors.textDisabled),
    };
    final who = criterion.checkedOnDevice ? l.critCheckedAuto : (criterion == SelfieCriterion.live ? l.critCheckedApp : l.critCheckedTeam);
    return Semantics(
      label: '${criterionTitle(l, criterion)}${state == false ? ' — ${l.critNotMet}' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(criterionTitle(l, criterion), style: context.type.bodyMedium.copyWith(fontWeight: state == false ? FontWeight.w600 : null)),
              if (showWho || state == null) Text(who, style: context.type.caption),
              if (state == false) Text(l.critNotMet, style: context.type.caption.copyWith(color: OlfaColors.primary)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _GestureCard extends StatelessWidget {
  const _GestureCard({required this.gesture});
  final SelfieGesture gesture;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final icon = switch (gesture) {
      SelfieGesture.thumbUp => Icons.thumb_up_alt_outlined,
      SelfieGesture.victory => Icons.back_hand_outlined,
      SelfieGesture.openPalm => Icons.front_hand_outlined,
      SelfieGesture.pointUp => Icons.touch_app_outlined,
      SelfieGesture.handOnChin => Icons.face_retouching_natural_outlined,
    };
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(OlfaRadius.card)),
      child: Column(children: [
        Icon(icon, size: 64, color: OlfaColors.primary),
        const SizedBox(height: 12),
        Text(gestureLabel(l, gesture), style: context.type.h2, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(l.selfieGestureHint, style: context.type.caption, textAlign: TextAlign.center),
      ]),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsetsDirectional.only(top: 7, end: 10), child: SizedBox.square(dimension: 6, child: DecoratedBox(decoration: BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle)))),
          Expanded(child: Text(text, style: context.type.bodyMedium)),
        ]),
      );
}
