import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../../shared/utils/phone_detect.dart';
import '../application/chat_controller.dart';
import '../data/chat_media.dart';

String _mmss(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Composer: text, up to 3 photos (preview tray with captions), and voice
/// notes (tap the mic to record, up to one minute; counter shows what the
/// plan has left in this conversation). Warns before sending a phone number.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key, required this.conversationId, required this.onSent, this.peerName});
  final String conversationId;
  final String? peerName;
  final VoidCallback onSent;
  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final _input = TextEditingController();
  final _photos = <PreparedPhoto>[];
  VoiceRecorder? _rec;
  Duration _elapsed = Duration.zero;
  StreamSubscription<Duration>? _tick;
  bool _preparing = false;
  bool _sending = false; // guards double taps while the phone check / send runs

  ChatController get _chat => ref.read(chatControllerProvider(widget.conversationId).notifier);

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      setState(() {});
      _chat.onInput(_input.text);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec?.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _addPhotos({bool camera = false}) async {
    final room = kMaxPhotosPerMessage - _photos.length;
    if (room <= 0) return showToast(context, AppLocalizations.of(context).maxPhotosPerMessage(kMaxPhotosPerMessage));
    setState(() => _preparing = true);
    try {
      final picked = await pickChatPhotos(max: room, camera: camera);
      if (mounted) setState(() => _photos.addAll(picked.take(room)));
    } catch (_) {
      if (mounted) showToast(context, AppLocalizations.of(context).photoAccessNeeded);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<bool> _confirmPhone(String text) async {
    if (!containsPhoneNumber(text)) return true;
    final l = AppLocalizations.of(context);
    return showConfirmation(context, title: l.phoneShareTitle, body: l.phoneShareBody, confirmLabel: l.sendAnyway, icon: Icons.shield_outlined);
  }

  Future<void> _send() async {
    final text = _input.text;
    if (_sending || (text.trim().isEmpty && _photos.isEmpty)) return;
    _sending = true;
    try {
      if (!await _confirmPhone(text)) return;
      final photos = List.of(_photos);
      final media = photos.isEmpty ? null : OutgoingMedia.photos(photos);
      _input.clear();
      setState(_photos.clear);
      final err = await _chat.send(text, media: media);
      widget.onSent();
      if (!mounted || err == null || err is NetworkFailure) return; // network: the bubble offers "retry"
      if (err is QuotaExceededFailure && _input.text.isEmpty) {
        // Nothing was sent: give the draft back so it isn't lost.
        _input.text = text;
        setState(() => _photos.addAll(photos));
      }
      showToast(context, failureMessage(context, err));
    } finally {
      _sending = false;
    }
  }

  Future<void> _startVoice() async {
    final l = AppLocalizations.of(context);
    final q = ref.read(voiceQuotaProvider(widget.conversationId)).valueOrNull;
    if (q?.remaining == 0) return _voiceLimit(q!.limit);
    final rec = VoiceRecorder()..onAutoStop = _finishVoice;
    if (!await rec.start()) {
      await rec.dispose();
      if (mounted) showToast(context, l.micAccessNeeded);
      return;
    }
    HapticFeedback.mediumImpact();
    _tick = rec.elapsed.listen((d) => setState(() => _elapsed = d));
    setState(() {
      _rec = rec;
      _elapsed = Duration.zero;
    });
  }

  void _voiceLimit(int limit) {
    final l = AppLocalizations.of(context);
    showConfirmation(context, title: l.voiceLimitTitle, body: l.voiceLimitBody(limit), confirmLabel: l.upgrade, icon: Icons.mic_off_rounded).then((ok) {
      if (ok && mounted) context.push(Routes.plans);
    });
  }

  Future<void> _finishVoice() async {
    final rec = _rec;
    if (rec == null) return;
    // Clear first: the 60 s auto-stop and a tap on "send" can arrive together.
    setState(() => _rec = null);
    final clip = await rec.stop();
    await _tick?.cancel();
    await rec.dispose();
    if (!mounted) return;
    if (clip == null) return;
    HapticFeedback.lightImpact();
    final err = await _chat.send('', media: OutgoingMedia.voice(clip));
    widget.onSent();
    if (err is QuotaExceededFailure && mounted) {
      _voiceLimit(ref.read(voiceQuotaProvider(widget.conversationId)).valueOrNull?.limit ?? 10);
    } else if (err != null && mounted && err is! NetworkFailure) {
      showToast(context, failureMessage(context, err));
    }
  }

  Future<void> _cancelVoice() async {
    final rec = _rec;
    setState(() => _rec = null);
    await _tick?.cancel();
    await rec?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final quota = ref.watch(voiceQuotaProvider(widget.conversationId)).valueOrNull;
    final canSend = _input.text.trim().isNotEmpty || _photos.isNotEmpty;
    return DecoratedBox(
      decoration: const BoxDecoration(color: OlfaColors.white, border: Border(top: BorderSide(color: OlfaColors.gray))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_photos.isNotEmpty || _preparing) _PhotoTray(photos: _photos, preparing: _preparing, onRemove: (i) => setState(() => _photos.removeAt(i))),
            if (_rec != null)
              _RecordingBar(elapsed: _elapsed, onCancel: _cancelVoice, onSend: _finishVoice)
            else
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                OlfaIconButton(icon: Icons.add_photo_alternate_outlined, tooltip: l.addPhotos, size: 44, onPressed: _preparing ? null : () => _addPhotos()),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _photos.isEmpty ? l.messageHint : l.addCaption,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      border: OutlineInputBorder(borderRadius: OlfaRadius.all(24), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: OlfaRadius.all(24), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: OlfaRadius.all(24), borderSide: const BorderSide(color: OlfaColors.primary, width: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (canSend)
                  // arrow_forward mirrors automatically in RTL.
                  OlfaIconButton(icon: Icons.arrow_forward_rounded, tooltip: l.send, style: OlfaIconStyle.filled, circle: true, size: 48, onPressed: _send)
                else
                  Stack(clipBehavior: Clip.none, children: [
                    OlfaIconButton(icon: Icons.mic_none_rounded, tooltip: l.recordVoice, style: OlfaIconStyle.filled, circle: true, size: 48, onPressed: _startVoice),
                    if (quota?.remaining != null)
                      PositionedDirectional(
                        top: -4,
                        end: -4,
                        child: Semantics(
                          label: l.voiceLeft(quota!.remaining!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: OlfaColors.black, borderRadius: OlfaRadius.all(9), border: Border.all(color: OlfaColors.white, width: 1.5)),
                            child: Text('${quota.remaining}', style: const TextStyle(color: OlfaColors.white, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'Montserrat')),
                          ),
                        ),
                      ),
                  ]),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _PhotoTray extends StatelessWidget {
  const _PhotoTray({required this.photos, required this.preparing, required this.onRemove});
  final List<PreparedPhoto> photos;
  final bool preparing;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 0, 8),
      child: SizedBox(
        height: 84,
        child: Row(children: [
          for (var i = 0; i < photos.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Stack(children: [
                ClipRRect(borderRadius: OlfaRadius.all(14), child: Image.file(File(photos[i].path), width: 84, height: 84, fit: BoxFit.cover, cacheWidth: 252)),
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: Semantics(
                    button: true,
                    label: l.removePhoto,
                    child: InkWell(
                      onTap: () => onRemove(i),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: OlfaColors.black, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, size: 14, color: OlfaColors.white),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          if (preparing) const SizedBox.square(dimension: 84, child: Center(child: CircularProgressIndicator(color: OlfaColors.primary, strokeWidth: 2))),
          const Spacer(),
          Text('${photos.length}/$kMaxPhotosPerMessage', style: context.type.caption),
          const SizedBox(width: 8),
        ]),
      ),
    );
  }
}

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.elapsed, required this.onCancel, required this.onSend});
  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final left = kMaxVoice - elapsed;
    return Semantics(
      liveRegion: true,
      label: l.recording,
      child: Row(children: [
        OlfaIconButton(icon: Icons.delete_outline_rounded, tooltip: l.cancel, size: 44, onPressed: onCancel),
        const SizedBox(width: 4),
        Container(width: 10, height: 10, decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(_mmss(elapsed.inMilliseconds), style: context.type.bodyMedium.copyWith(fontFamily: 'Montserrat', fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: OlfaRadius.all(4),
            child: LinearProgressIndicator(value: (elapsed.inMilliseconds / kMaxVoice.inMilliseconds).clamp(0.0, 1.0).toDouble(), minHeight: 5, color: OlfaColors.primary, backgroundColor: OlfaColors.gray),
          ),
        ),
        const SizedBox(width: 8),
        Text(l.secondsLeft(left.inSeconds.clamp(0, 60).toInt()), style: context.type.caption),
        const SizedBox(width: 6),
        OlfaIconButton(icon: Icons.arrow_upward_rounded, tooltip: l.send, style: OlfaIconStyle.filled, circle: true, size: 48, onPressed: onSend),
      ]),
    );
  }
}

/// Photos inside a bubble: 1 large, 2 side by side, 3 as one + two.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.items, required this.maxWidth});
  final List<ChatAttachment> items;
  final double maxWidth;

  Widget _img(BuildContext context, ChatAttachment a, double w, double h) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final image = a.localPath != null
        ? Image.file(File(a.localPath!), width: w, height: h, fit: BoxFit.cover, cacheWidth: (w * dpr).round())
        : Image.network(a.url ?? '', width: w, height: h, fit: BoxFit.cover, cacheWidth: (w * dpr).round(),
            errorBuilder: (_, __, ___) => Container(width: w, height: h, color: OlfaColors.gray, child: const Icon(Icons.broken_image_outlined)));
    return GestureDetector(onTap: () => _open(context, a), child: ClipRRect(borderRadius: OlfaRadius.all(14), child: image));
  }

  void _open(BuildContext context, ChatAttachment a) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: OlfaColors.black,
        appBar: AppBar(backgroundColor: OlfaColors.black, foregroundColor: OlfaColors.white),
        body: Center(
          child: InteractiveViewer(
            child: a.localPath != null ? Image.file(File(a.localPath!)) : Image.network(a.url ?? ''),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final w = maxWidth;
    const gap = 4.0;
    return switch (items.length) {
      1 => _img(context, items[0], w, w * 0.8),
      2 => Row(mainAxisSize: MainAxisSize.min, children: [_img(context, items[0], (w - gap) / 2, w * 0.6), const SizedBox(width: gap), _img(context, items[1], (w - gap) / 2, w * 0.6)]),
      _ => Column(mainAxisSize: MainAxisSize.min, children: [
          _img(context, items[0], w, w * 0.55),
          const SizedBox(height: gap),
          Row(mainAxisSize: MainAxisSize.min, children: [_img(context, items[1], (w - gap) / 2, w * 0.4), const SizedBox(width: gap), _img(context, items[2], (w - gap) / 2, w * 0.4)]),
        ]),
    };
  }
}

/// Voice-note bubble: play / pause, waveform progress, duration, speed.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.attachment, required this.mine});
  final ChatAttachment attachment;
  final bool mine;
  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final _player = AudioPlayer();
  bool _ready = false;
  double _speed = 1;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) {
      final a = widget.attachment;
      await (a.localPath != null ? _player.setFilePath(a.localPath!) : _player.setUrl(a.url ?? ''));
      _ready = true;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) await _player.seek(Duration.zero);
      unawaited(_player.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fg = widget.mine ? OlfaColors.white : OlfaColors.black;
    final total = widget.attachment.durationMs ?? 0;
    final wave = widget.attachment.waveform.isEmpty ? List.filled(48, 20) : widget.attachment.waveform;
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final pos = snap.data?.inMilliseconds ?? 0;
        final progress = total == 0 ? 0.0 : (pos / total).clamp(0.0, 1.0).toDouble();
        return Semantics(
          label: l.voiceMessage(_mmss(total)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            StreamBuilder<bool>(
              stream: _player.playingStream,
              builder: (_, p) => IconButton(
                tooltip: (p.data ?? false) ? l.pause : l.play,
                onPressed: _toggle,
                icon: Icon((p.data ?? false) ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 38, color: fg),
              ),
            ),
            SizedBox(
              width: 150,
              height: 32,
              child: GestureDetector(
                onTapDown: (d) {
                  if (!_ready || total == 0) return;
                  final dx = Directionality.of(context) == TextDirection.rtl ? 150 - d.localPosition.dx : d.localPosition.dx;
                  _player.seek(Duration(milliseconds: (dx / 150 * total).round()));
                },
                child: CustomPaint(painter: _WavePainter(wave, progress, fg, Directionality.of(context))),
              ),
            ),
            const SizedBox(width: 8),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_mmss(pos > 0 ? pos : total), style: TextStyle(fontSize: 11, color: fg, fontFamily: 'Montserrat')),
              InkWell(
                onTap: () {
                  setState(() => _speed = _speed == 1 ? 1.5 : (_speed == 1.5 ? 2 : 1));
                  _player.setSpeed(_speed);
                },
                child: Text('${_speed == 1 ? '1' : _speed}×', style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.8), fontWeight: FontWeight.w700, fontFamily: 'Montserrat')),
              ),
            ]),
          ]),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.peaks, this.progress, this.color, this.dir);
  final List<int> peaks;
  final double progress;
  final Color color;
  final TextDirection dir;

  @override
  void paint(Canvas canvas, Size size) {
    final n = peaks.length;
    final bw = size.width / n;
    for (var i = 0; i < n; i++) {
      final h = (peaks[i] / 100).clamp(0.08, 1.0) * size.height;
      final x = dir == TextDirection.rtl ? size.width - (i + 1) * bw : i * bw;
      final played = i / n <= progress;
      final p = Paint()..color = played ? color : color.withValues(alpha: 0.38);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + bw * 0.2, (size.height - h) / 2, bw * 0.6, h), const Radius.circular(2)), p);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress || old.peaks != peaks || old.color != color;
}

/// Safety note under a message that contains a phone number — shown to both people.
class PhoneSafetyNote extends StatelessWidget {
  const PhoneSafetyNote({super.key, required this.mine});
  final bool mine;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: OlfaColors.primaryTint(), borderRadius: OlfaRadius.all(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_outlined, size: 16, color: OlfaColors.primary),
        const SizedBox(width: 6),
        Flexible(child: Text(mine ? l.phoneSentNote : l.phoneReceivedNote, style: context.type.caption.copyWith(color: OlfaColors.black))),
      ]),
    );
  }
}
