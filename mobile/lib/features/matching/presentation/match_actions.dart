import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/navigation.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../data/matching_repository_impl.dart';

/// Opens the chat with a match — or starts it (one daily start-credit, after a
/// confirmation). Used by Matches and by the profile page, so both behave the same.
/// Returns once the chat is open, or when the member cancelled / had no credit.
Future<void> openMatchChat(BuildContext context, WidgetRef ref, MatchItem m) async {
  if (m.conversationId != null) {
    await context.pushOnce(Routes.chatWith(m.conversationId!));
    return;
  }
  final l = AppLocalizations.of(context);
  final ent = ref.read(entitlementsProvider).valueOrNull;
  if (ent != null && ent.messagesLeft <= 0) {
    showToast(context, l.quotaMessages);
    return;
  }
  final ok = await showConfirmation(
    context,
    title: l.startConversationTitle(m.peer.name),
    body: l.startConversationBody(ent?.messagesLeft ?? 0),
    confirmLabel: l.startConversation,
    icon: Icons.chat_bubble_outline_rounded,
  );
  if (!ok || !context.mounted) return;
  try {
    final id = await ref.read(matchingRepositoryProvider).startConversation(m.id);
    await ref.read(entitlementsProvider.notifier).refresh();
    ref.invalidate(matchesProvider);
    if (context.mounted) await context.pushOnce(Routes.chatWith(id));
  } catch (e) {
    if (context.mounted) showToast(context, failureMessage(context, e));
  }
}
