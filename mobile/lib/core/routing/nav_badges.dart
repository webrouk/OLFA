import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/consultations/application/consultation_providers.dart';
import '../../features/matching/data/matching_repository_impl.dart';
import '../../features/messaging/data/messaging_repository_impl.dart';
import '../../shared/models/models.dart';

/// Badge counts on the bottom navigation, from real data only (0 = no badge).
/// Each count is a `select`, so the bar rebuilds only when a number changes.

/// Member tabs: 0 Discover · 1 Likes · 2 Matches · 3 Messages · 4 Profile.
final memberNavBadgesProvider = Provider.autoDispose<Map<int, int>>((ref) {
  final likes = ref.watch(likesReceivedProvider.select((v) => v.valueOrNull?.count ?? 0));
  final newMatches = ref.watch(matchesProvider.select((v) => v.valueOrNull?.where((m) => m.isNew && m.conversationId == null).length ?? 0));
  final unread = ref.watch(unreadMessagesProvider);
  return {1: likes, 2: newMatches, 3: unread};
});

/// Professional tabs: 0 Desk · 1 Wallet · 2 Messages · 3 Profile.
final professionalNavBadgesProvider = Provider.autoDispose<Map<int, int>>((ref) {
  // Paid requests waiting for the counselor to confirm.
  final waiting = ref.watch(counselorDeskProvider.select((v) => v.valueOrNull?.where((c) => c.status == ConsultationStatus.paid).length ?? 0));
  return {0: waiting, 2: ref.watch(unreadMessagesProvider)};
});

/// Conversations with unread messages (not the number of messages: one badge per person).
final unreadMessagesProvider = Provider<int>(
  (ref) => ref.watch(conversationIndexProvider.select((v) => v.valueOrNull?.visible.where((c) => c.unread > 0).length ?? 0)),
);
