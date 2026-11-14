import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../shared/models/models.dart';

/// Up to 3 photos per message.
const kMaxPhotosPerMessage = 3;

/// Voice notes stop on their own at one minute.
const kMaxVoice = Duration(seconds: 60);

/// Picks up to [max] photos and compresses each on the device: long side
/// ≤ 2048 px, JPEG quality 86, metadata (EXIF/GPS) removed. At phone-screen
/// sizes this is visually lossless while cutting a 4–8 MB camera photo to
/// roughly 300–700 KB. The server re-encodes once more to guarantee no
/// metadata survives.
Future<List<PreparedPhoto>> pickChatPhotos({int max = kMaxPhotosPerMessage, bool camera = false}) async {
  final picker = ImagePicker();
  final picked = camera
      ? [if (await picker.pickImage(source: ImageSource.camera, requestFullMetadata: false) case final x?) x]
      : await picker.pickMultiImage(limit: max, requestFullMetadata: false);
  final out = <PreparedPhoto>[];
  for (final x in picked.take(max)) {
    out.add(await compressChatPhoto(x.path));
  }
  return out;
}

Future<PreparedPhoto> compressChatPhoto(String path) async {
  final dir = await getTemporaryDirectory();
  final target = '${dir.path}/olfa_${DateTime.now().microsecondsSinceEpoch}.jpg';
  final file = await FlutterImageCompress.compressAndGetFile(
    path,
    target,
    minWidth: 2048,
    minHeight: 2048, // "min" = the long side is scaled down to 2048, never up
    quality: 86,
    keepExif: false,
    format: CompressFormat.jpeg,
  );
  final bytes = await (file != null ? File(file.path) : File(path)).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final w = frame.image.width, h = frame.image.height;
  frame.image.dispose();
  return PreparedPhoto(path: file?.path ?? path, bytes: bytes, width: w, height: h);
}

/// Records a voice note: AAC-LC, 48 kHz mono, 96 kbps (clear speech at a
/// small size), noise suppression and echo cancellation on, auto-stop at 60 s.
/// Collects a 48-bar waveform from the input level.
class VoiceRecorder {
  final _rec = AudioRecorder();
  final _levels = <double>[];
  StreamSubscription<Amplitude>? _amp;
  Timer? _limit;
  DateTime? _started;
  String? _path;
  final _elapsed = StreamController<Duration>.broadcast();
  void Function()? onAutoStop;

  Stream<Duration> get elapsed => _elapsed.stream;
  bool get isRecording => _started != null;

  Future<bool> hasPermission() => _rec.hasPermission();

  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/olfa_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _levels.clear();
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 48000,
        bitRate: 96000,
        numChannels: 1,
        noiseSuppress: true,
        echoCancel: true,
        autoGain: true,
      ),
      path: _path!,
    );
    _started = DateTime.now();
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      // dBFS (-60..0) → 0..1
      _levels.add(((a.current + 60) / 60).clamp(0.0, 1.0).toDouble());
      _elapsed.add(DateTime.now().difference(_started!));
    });
    _limit = Timer(kMaxVoice, () => onAutoStop?.call());
    return true;
  }

  /// Finishes the note; null if it was shorter than half a second.
  Future<VoiceClip?> stop() async {
    final started = _started;
    _limit?.cancel();
    await _amp?.cancel();
    final path = await _rec.stop();
    _started = null;
    if (path == null || started == null) return null;
    final ms = math.min(DateTime.now().difference(started).inMilliseconds, kMaxVoice.inMilliseconds);
    if (ms < 500) return null;
    final bytes = await File(path).readAsBytes();
    return VoiceClip(path: path, bytes: bytes, durationMs: ms, waveform: waveformOf(_levels));
  }

  Future<void> cancel() async {
    _limit?.cancel();
    await _amp?.cancel();
    await _rec.cancel();
    _started = null;
  }

  Future<void> dispose() async {
    await cancel();
    await _elapsed.close();
    _rec.dispose();
  }
}

/// Resamples input levels to [bars] peaks in 0..100 (shown in the bubble).
List<int> waveformOf(List<double> levels, {int bars = 48}) {
  if (levels.isEmpty) return List.filled(bars, 8);
  return List.generate(bars, (i) {
    final a = (i * levels.length / bars).floor();
    final b = math.max(a + 1, ((i + 1) * levels.length / bars).floor());
    final peak = levels.sublist(a, math.min(b, levels.length)).fold<double>(0, math.max);
    return (8 + peak * 92).round().clamp(0, 100);
  });
}
