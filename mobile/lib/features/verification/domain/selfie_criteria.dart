/// Selfie verification criteria — the same list as the server
/// (backend/src/domain/selfie.ts) and docs/VERIFICATION.md.
///
/// C1 live       taken now in the app with the front camera (one-time capture + random gesture)
/// C2 oneFace    exactly one face
/// C3 visible    whole face visible and close enough (≥ 25 % of the width), eyes open, nothing covering it
/// C4 straight   looking at the camera (turn / tilt ≤ 20°)
/// C5 quality    sharp, well lit, ≥ 480 px on the short side, no filters or edits
/// C6 gesture    shows the requested gesture                 (verification team)
/// C7 samePerson same person as in the profile photos        (verification team)
/// C8 real       a real person, not a screen or a printed photo (verification team)
enum SelfieCriterion {
  live,
  oneFace,
  visible,
  straight,
  quality,
  gesture,
  samePerson,
  real;

  static SelfieCriterion? fromApi(String s) => SelfieCriterion.values.where((c) => c.name == s).firstOrNull;

  /// Checked automatically on the phone before upload.
  bool get checkedOnDevice => this == oneFace || this == visible || this == straight || this == quality;
}

enum SelfieGesture {
  thumbUp('thumb_up'),
  victory('victory'),
  openPalm('open_palm'),
  pointUp('point_up'),
  handOnChin('hand_on_chin');

  const SelfieGesture(this.api);
  final String api;
  static SelfieGesture fromApi(String? s) => SelfieGesture.values.firstWhere((g) => g.api == s, orElse: () => SelfieGesture.thumbUp);
}

abstract final class SelfieLimits {
  static const minFaceRatio = 0.25;
  static const maxAngle = 20.0;
  static const minEyeOpen = 0.4;
  static const minShortSide = 480;
  static const minBrightness = 45;
  static const maxBrightness = 225;
}

/// What the phone measured (face detection + picture size/brightness).
class DeviceChecks {
  const DeviceChecks({required this.faces, required this.faceRatio, required this.yaw, required this.roll, this.leftEyeOpen, this.rightEyeOpen, required this.width, required this.height, required this.brightness});
  final int faces;
  final double faceRatio;
  final double yaw;
  final double roll;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final int width;
  final int height;
  final double brightness; // mean luminance 0–255

  Map<String, Object?> toJson() => {
        'faces': faces,
        'faceRatio': double.parse(faceRatio.toStringAsFixed(3)),
        'yaw': double.parse(yaw.toStringAsFixed(1)),
        'roll': double.parse(roll.toStringAsFixed(1)),
        if (leftEyeOpen != null) 'leftEyeOpen': double.parse(leftEyeOpen!.toStringAsFixed(2)),
        if (rightEyeOpen != null) 'rightEyeOpen': double.parse(rightEyeOpen!.toStringAsFixed(2)),
      };
}

/// Criteria the phone found unmet (empty = upload for review). Mirrors the server rule.
List<SelfieCriterion> failedDeviceChecks(DeviceChecks d) {
  final out = <SelfieCriterion>{};
  if (d.faces != 1) out.add(SelfieCriterion.oneFace);
  if (d.faces >= 1) {
    if (d.faceRatio < SelfieLimits.minFaceRatio) out.add(SelfieCriterion.visible);
    final eyes = [d.leftEyeOpen, d.rightEyeOpen].whereType<double>();
    if (eyes.isNotEmpty && eyes.reduce((a, b) => a < b ? a : b) < SelfieLimits.minEyeOpen) out.add(SelfieCriterion.visible);
    if (d.yaw.abs() > SelfieLimits.maxAngle || d.roll.abs() > SelfieLimits.maxAngle) out.add(SelfieCriterion.straight);
  }
  final short = d.width < d.height ? d.width : d.height;
  if (short < SelfieLimits.minShortSide || d.brightness < SelfieLimits.minBrightness || d.brightness > SelfieLimits.maxBrightness) out.add(SelfieCriterion.quality);
  return SelfieCriterion.values.where(out.contains).toList();
}
