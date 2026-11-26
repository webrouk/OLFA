import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/features/verification/domain/selfie_criteria.dart';

void main() {
  const good = DeviceChecks(faces: 1, faceRatio: 0.4, yaw: 3, roll: -2, leftEyeOpen: 0.9, rightEyeOpen: 0.8, width: 1080, height: 1440, brightness: 120);
  DeviceChecks w({int? faces, double? ratio, double? yaw, double? eye, int? width, double? light}) => DeviceChecks(
        faces: faces ?? good.faces,
        faceRatio: ratio ?? good.faceRatio,
        yaw: yaw ?? good.yaw,
        roll: good.roll,
        leftEyeOpen: eye ?? good.leftEyeOpen,
        rightEyeOpen: good.rightEyeOpen,
        width: width ?? good.width,
        height: good.height,
        brightness: light ?? good.brightness,
      );

  test('a clear selfie passes', () => expect(failedDeviceChecks(good), isEmpty));
  test('no face or two faces', () {
    expect(failedDeviceChecks(w(faces: 0)), [SelfieCriterion.oneFace]);
    expect(failedDeviceChecks(w(faces: 2)), [SelfieCriterion.oneFace]);
  });
  test('too far, eyes closed, turned', () {
    expect(failedDeviceChecks(w(ratio: 0.1)), [SelfieCriterion.visible]);
    expect(failedDeviceChecks(w(eye: 0.1)), [SelfieCriterion.visible]);
    expect(failedDeviceChecks(w(yaw: 30)), [SelfieCriterion.straight]);
  });
  test('small or dark picture', () {
    expect(failedDeviceChecks(w(width: 400)), [SelfieCriterion.quality]);
    expect(failedDeviceChecks(w(light: 20)), [SelfieCriterion.quality]);
  });
}
