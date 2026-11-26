import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../domain/selfie_criteria.dart';

/// Measures a selfie on the phone (nothing leaves the device for this):
/// faces (ML Kit face detection, on-device), face size, head angles, eyes open,
/// picture size and brightness.
class SelfieAnalyzer {
  Future<DeviceChecks> analyze(String path, Uint8List bytes) async {
    final detector = FaceDetector(options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.1));
    try {
      final faces = await detector.processImage(InputImage.fromFilePath(path));
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64); // small copy for brightness
      final frame = await codec.getNextFrame();
      final full = await ui.instantiateImageCodec(bytes);
      final size = (await full.getNextFrame()).image;
      final brightness = await _brightness(frame.image);
      final f = faces.isEmpty ? null : faces.reduce((a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
      return DeviceChecks(
        faces: faces.length,
        faceRatio: f == null ? 0 : (f.boundingBox.width / size.width).clamp(0, 1).toDouble(),
        yaw: f?.headEulerAngleY ?? 0,
        roll: f?.headEulerAngleZ ?? 0,
        leftEyeOpen: f?.leftEyeOpenProbability,
        rightEyeOpen: f?.rightEyeOpenProbability,
        width: size.width,
        height: size.height,
        brightness: brightness,
      );
    } finally {
      await detector.close();
    }
  }

  Future<double> _brightness(ui.Image img) async {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return 128;
    var sum = 0.0;
    final n = data.lengthInBytes ~/ 4;
    for (var i = 0; i < n; i++) {
      final o = i * 4;
      sum += 0.299 * data.getUint8(o) + 0.587 * data.getUint8(o + 1) + 0.114 * data.getUint8(o + 2);
    }
    return n == 0 ? 128 : sum / n;
  }

  /// Removes the temporary capture from the phone.
  Future<void> discard(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
