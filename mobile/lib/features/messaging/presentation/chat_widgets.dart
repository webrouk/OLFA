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

/// Unsent text per conversation, kept while the app runs (leaving a chat and
/// coming back keeps what you were typing).
final chatDraftsProvider = StateProvider<Map<String, String>>((_) => const {});

enum _Voice { idle, holding, locked, review }

/// Composer: text (draft kept per conversation), up to 3 photos from the
/// gallery or camera (preview tray, the text becomes the caption), and voice
/// notes up to one minute:
///  - hold the mic to record, release to send; slide toward the start to cancel,
///    slide up to lock and keep recording hands-free;
///  - or tap the mic: records locked (accessible without holding);
///  - locked recordings can be stopped and listened to before sending.
/// Warns before sending a phone number.
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
  _Voice _voice = _Voice.idle;
  VoiceClip? _clip; // recorded, waiting in review
  double _dx = 0, _dy = 0; // finger travel while holding
  Duration _elapsed = Duration.zero;
  StreamSubscription<Duration>? _tick;
  bool _preparing = false;
  bool _sending = false; // guards double taps while the phone check / send runs

  static const _cancelAt = 110.0, _lockAt = 70.0;

  ChatController get _chat => ref.read(chatControllerProvider(widget.conversationId).notifier);

  @override
  void initState() {
    super.initState();
    _input.text = ref.read(chatDraftsProvider)[widget.conversationId] ?? '';
    _input.addListener(() {
      setState(() {});
      _chat.onInput(_input.text);
      final drafts = ref.read(chatDraftsProvider.notifier);
      final t = _input.text;
      if ((drafts.state[widget.conversationId] ?? '') != t) {
        drafts.state = {...drafts.state, widget.conversationId: t}..removeWhere((_, v) => v.isEmpty);
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec?.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    final l = AppLocalizations.of(context);
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(l.attachPhoto), onTap: () => Navigator.pop(c, false)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(l.attachCamera), onTap: () => Navigator.pop(c, true)),
        ]),
      ),
    );
    if (camera != null) await _addPhotos(camera: camera);
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
      if (!mounted || err == null || err is NetworkFailure) return; // offline: queued on the phone, sent by itself
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

  Future<void> _startVoice({required bool locked}) async {
    if (_rec != null || _voice != _Voice.idle) return;
    final l = AppLocalizations.of(context);
    final q = ref.read(voiceQuotaProvider(widget.conversationId)).valueOrNull;
    if (q?.remaining == 0) return _voiceLimit(q!.limit);
    final rec = VoiceRecorder()..onAutoStop = () => _voice == _Voice.locked ? _stopToReview() : _finishVoice();
    // shown immediately so the gesture feels instant; reset if the mic is refused
    setState(() {
      _voice = locked ? _Voice.locked : _Voice.holding;
      _dx = _dy = 0;
      _elapsed = Duration.zero;
    });
    if (!await rec.start()) {
      await rec.dispose();
      if (mounted) {
        setState(() => _voice = _Voice.idle);
        showToast(context, l.micAccessNeeded);
      }
      return;
    }
    if (!mounted || _voice == _Voice.idle) {
      // released before the recorder started
      await rec.dispose();
      return;
    }
    HapticFeedback.mediumImpact();
    _tick = rec.elapsed.listen((d) => setState(() => _elapsed = d));
    setState(() => _rec = rec);
  }

  void _voiceLimit(int limit) {
    final l = AppLocalizations.of(context);
    showConfirmation(context, title: l.voiceLimitTitle, body: l.voiceLimitBody(limit), confirmLabel: l.upgrade, icon: Icons.mic_off_rounded).then((ok) {
      if (ok && mounted) context.push(Routes.plans);
    });
  }

  Future<VoiceClip?> _stopRecorder() async {
    final rec = _rec;
    _rec = null;
    if (rec == null) return null;
    final clip = await rec.stop();
    await _tick?.cancel();
    await rec.dispose();
    return clip;
  }

  /// Release while holding, or "send" while locked / reviewing.
  Future<void> _finishVoice() async {
    final clip = _clip ?? await _stopRecorder();
    setState(() {
      _voice = _Voice.idle;
      _clip = null;
    });
    if (!mounted) return;
    if (clip == null) {
      showToast(context, AppLocalizations.of(context).voiceTooShort);
      return;
    }
    HapticFeedback.lightImpact();
    final err = await _chat.send('', media: OutgoingMedia.voice(clip));
    widget.onSent();
    if (err is QuotaExceededFailure && mounted) {
      _voiceLimit(ref.read(voiceQuotaProvider(widget.conversationId)).valueOrNull?.limit ?? 10);
    } else if (err != null && mounted && err is! NetworkFailure) {
      showToast(context, failureMessage(context, err));
    }
  }

  /// Locked recording → stop and listen before sending.
  Future<void> _stopToReview() async {
    final clip = await _stopRecorder();
    if (!mounted) return;
    setState(() {
      _clip = clip;
      _voice = clip == null ? _Voice.idle : _Voice.review;
    });
    if (clip == null) showToast(context, AppLocalizations.of(context).voiceTooShort);
  }

  Future<void> _cancelVoice() async {
    final rec = _rec;
    _rec = null;
    setState(() {
      _voice = _Voice.idle;
      _clip = null;
    });
    await _tick?.cancel();
    await rec?.dispose();
    HapticFeedback.selectionClick();
  }

  void _onHoldMove(LongPressMoveUpdateDetails d) {
    if (_voice != _Voice.holding) return;
    // The composer keeps send / mic on the right in every language, so
    // "slide to cancel" is always toward the left (away from the button).
    final toStart = -d.offsetFromOrigin.dx;
    setState(() {
      _dx = toStart.clamp(0, _cancelAt + 20).toDouble();
      _dy = (-d.offsetFromOrigin.dy).clamp(0, _lockAt + 20).toDouble();
    });
    if (toStart > _cancelAt) {
      _cancelVoice();
    } else if (-d.offsetFromOrigin.dy > _lockAt) {
      HapticFeedback.mediumImpact();
      setState(() => _voice = _Voice.locked);
    }
  }

  void _onHoldEnd() {
    if (_voice == _Voice.holding) _finishVoice();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final quota = ref.watch(voiceQuotaProvider(widget.conversationId)).valueOrNull;
    final canSend = _input.text.trim().isNotEmpty || _photos.isNotEmpty;
    final mic = GestureDetector(
      onLongPressStart: (_) => _startVoice(locked: false),
      onLongPressMoveUpdate: _onHoldMove,
      onLongPressEnd: (_) => _onHoldEnd(),
      onLongPressCancel: _onHoldEnd,
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedScale(
          scale: _voice == _Voice.holding ? 1.25 : 1,
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
          child: OlfaIconButton(icon: Icons.mic_none_rounded, tooltip: l.recordVoiceHint, style: OlfaIconStyle.filled, circle: true, size: 48, onPressed: () => _startVoice(locked: true)),
        ),
        if (quota?.remaining != null && _voice == _Voice.idle)
          PositionedDirectional(
            top: -4,
            end: -4,
            child: Semantics(
              label: l.voiceLeft(quota!.remaining!),
              child: CountBadge(count: quota.remaining!, inverted: true),
            ),
          ),
        // slide up to lock
        if (_voice == _Voice.holding)
          PositionedDirectional(
            bottom: 56 + _dy,
            end: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(color: OlfaColors.white, borderRadius: OlfaRadius.all(18), border: Border.all(color: OlfaColors.gray)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_dy > _lockAt * 0.6 ? Icons.lock_rounded : Icons.lock_open_rounded, size: 18, color: OlfaColors.primary),
                const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: OlfaColors.textMuted),
              ]),
            ),
          ),
      ]),
    );
    // Send / mic sit on the RIGHT of the text field in every language (Arabic
    // included), attachments on the left: the row is laid out left-to-right
    // while the field itself keeps the reading direction.
    final reading = Directionality.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(color: OlfaColors.white, border: Border(top: BorderSide(color: OlfaColors.gray))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Directionality(
           textDirection: TextDirection.ltr,
           child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_photos.isNotEmpty || _preparing) _PhotoTray(photos: _photos, preparing: _preparing, onRemove: (i) => setState(() => _photos.removeAt(i))),
            switch (_voice) {
              _Voice.review => _VoiceReview(clip: _clip!, onDelete: _cancelVoice, onSend: _finishVoice),
              _Voice.locked => _RecordingBar(elapsed: _elapsed, onCancel: _cancelVoice, onSend: _finishVoice, onStop: _stopToReview),
              // idle and holding share one row so the mic keeps its place in the tree:
              // the press that starts a hold must survive the switch to the holding bar.
              _ => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: _voice == _Voice.holding
                        ? _HoldingBar(elapsed: _elapsed, slide: _dx / _cancelAt)
                        : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            OlfaIconButton(icon: Icons.add_photo_alternate_outlined, tooltip: l.addPhotos, size: 44, onPressed: _preparing ? null : _pickSource),
                            Expanded(
                              child: Directionality(
                               textDirection: reading,
                               child: TextField(
                                controller: _input,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: 2000,
                                textCapitalization: TextCapitalization.sentences,
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
                            ),
                          ]),
                  ),
                  const SizedBox(width: 6),
                  if (canSend && _voice == _Voice.idle)
                    // an upward arrow reads the same in both directions
                    OlfaIconButton(icon: Icons.arrow_upward_rounded, tooltip: l.send, style: OlfaIconStyle.filled, circle: true, size: 48, onPressed: _send)
                  else
                    mic,
                ]),
            },
            if (_input.text.length > 1800 && _voice == _Voice.idle)
              Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(right: 60, top: 2), child: Text('${_input.text.length}/2000', style: context.type.caption))),
          ]),
          ),
        ),
      ),
    );
  }
}

/// While holding the mic: timer + "slide to cancel" that fades as the finger moves.
class _HoldingBar extends StatelessWidget {
  const _HoldingBar({required this.elapsed, required this.slide});
  final Duration elapsed;
  final double slide; // 0..1 toward cancelling
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label: l.recording,
      child: SizedBox(
        height: 48,
        child: Row(children: [
          const SizedBox(width: 10),
          Container(width: 10, height: 10, decoration: const BoxDecoration(color: OlfaColors.primary, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(_mmss(elapsed.inMilliseconds), style: context.type.bodyMedium.copyWith(fontFamily: 'Montserrat', fontWeight: FontWeight.w600)),
          const Spacer(),
          Opacity(
            opacity: (1 - slide).clamp(0.2, 1.0).toDouble(),
            child: Row(children: [
              const Icon(Icons.chevron_left_rounded, color: OlfaColors.textMuted), // the composer is laid out left-to-right: always toward the left
              Text(l.slideToCancel, style: context.type.bodySmall.copyWith(color: OlfaColors.textMuted)),
            ]),
          ),
          const SizedBox(width: 6),
        ]),
      ),
    );
  }
}

/// A stopped recording: listen, then delete or send.
class _VoiceReview extends StatefulWidget {
  const _VoiceReview({required this.clip, required this.onDelete, required this.onSend});
  final VoiceClip clip;
  final VoidCallback onDelete;
  final VoidCallback onSend;
  @override
  State<_VoiceReview> createState() => _VoiceReviewState();
}

class _VoiceReviewState extends State<_VoiceReview> {
  final _player = AudioPlayer();
  bool _ready = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) {
      await _player.setFilePath(widget.clip.path);
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
    final total = widget.clip.durationMs;
    return Row(children: [
      OlfaIconButton(icon: Icons.delete_outline_rounded, tooltip: l.deleteRecording, size: 44, onPressed: widget.onDelete),
      Expanded(
        child: Container(
          height: 48,
          padding: const EdgeInsetsDirectional.only(end: 12),
          decoration: BoxDecoration(color: OlfaColors.gray, borderRadius: OlfaRadius.all(24)),
          child: StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snap) {
              final pos = snap.data?.inMilliseconds ?? 0;
              final progress = total == 0 ? 0.0 : (pos / total).clamp(0.0, 1.0).toDouble();
              return Row(children: [
                StreamBuilder<bool>(
                  stream: _player.playingStream,
                  builder: (_, p) => IconButton(
                    tooltip: (p.data ?? false) ? l.pause : l.listenBeforeSending,
                    onPressed: _toggle,
                    icon: Icon((p.data ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded, color: OlfaColors.primary),
                  ),
                ),
                Expanded(child: SizedBox(height: 28, child: CustomPaint(painter: _WavePainter(widget.clip.waveform, progress, OlfaColors.black, Directionality.of(context))))),
                const SizedBox(width: 8),
                Text(_mmss(pos > 0 ? pos : total), style: const TextStyle(fontSize: 12, fontFamily: 'Montserrat', fontWeight: FontWeight.w600)),
              ]);
            },
          ),
        ),
      ),
      const SizedBox(width: 6),
      OlfaIconButton(icon: Icons.arrow_upward_rounded, tooltip: l.send, style: OlfaIconStyle.filled, circle: true, size: 48, onPressed: widget.onSend),
    ]);
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
  const _RecordingBar({required this.elapsed, required this.onCancel, required this.onSend, required this.onStop});
  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  final VoidCallback onStop; // stop and listen before sending

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
        const SizedBox(width: 4),
        OlfaIconButton(icon: Icons.stop_circle_outlined, tooltip: l.stopAndListen, size: 44, onPressed: onStop),
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
