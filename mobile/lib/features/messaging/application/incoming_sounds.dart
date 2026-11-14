import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sound/sound_service.dart';
import '../data/messaging_repository_impl.dart';

/// Plays the message tone for incoming messages while the app is open
/// (push sounds cover the background). Watched once by the app root.
final incomingSoundsProvider = Provider<void>((ref) {
  final repo = ref.watch(messagingRepositoryProvider);
  final sounds = ref.watch(soundServiceProvider);
  sounds.enabled = ref.watch(soundsEnabledProvider);
  final sub = repo.events().listen((e) {
    final m = e.message;
    if (m != null && !m.fromMe) sounds.play(OlfaSound.message);
  });
  ref.onDispose(sub.cancel);
});
