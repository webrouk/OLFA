import '../../../shared/models/models.dart';

/// Thread ordering, shared by the chat and its tests:
///  - messages the server accepted are ordered by their server position (seq);
///  - messages still on the phone (queued / sending / failed) come after them,
///    in the order they were written;
///  - the same message never appears twice (idempotency key), and the server copy
///    wins over the local one.
List<ChatMessage> mergeThread(Iterable<ChatMessage> current, Iterable<ChatMessage> incoming) {
  final byKey = <String, ChatMessage>{};
  for (final m in [...current, ...incoming]) {
    final prev = byKey[m.clientId];
    byKey[m.clientId] = prev == null ? m : _prefer(prev, m);
  }
  final list = byKey.values.toList();
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = _compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1); // stable
  });
  return [for (final e in indexed) e.$2];
}

ChatMessage _prefer(ChatMessage a, ChatMessage b) {
  // a server-confirmed copy beats a local one; between two confirmed copies keep the
  // most advanced status (read > delivered > sent) and any local file preview
  if (a.seq == null && b.seq != null) return _keepPreview(b, a);
  if (b.seq == null && a.seq != null) return a;
  if (a.seq == null && b.seq == null) return b; // newer local state (e.g. failed → sending)
  final best = _rank(b.status) >= _rank(a.status) ? b : a.copyWith(attachments: b.attachments.isEmpty ? a.attachments : b.attachments);
  return _keepPreview(best, a);
}

/// Keeps the sender's local file until the signed URL arrives.
ChatMessage _keepPreview(ChatMessage server, ChatMessage local) =>
    server.attachments.isNotEmpty && server.attachments.first.url == null && local.attachments.isNotEmpty ? server.copyWith(attachments: local.attachments) : server;

int _rank(MessageStatus s) => switch (s) {
      MessageStatus.read => 4,
      MessageStatus.delivered => 3,
      MessageStatus.sent => 2,
      _ => 1,
    };

int _compare(ChatMessage a, ChatMessage b) {
  final pa = a.seq == null, pb = b.seq == null;
  if (!pa && !pb) return a.seq!.compareTo(b.seq!);
  if (pa != pb) {
    // demo data has no positions: then time decides
    if (!a.isPending && !b.isPending) return a.sentAt.compareTo(b.sentAt);
    return pa ? 1 : -1;
  }
  // both without a position: confirmed (demo) before pending, then by time written
  if (a.isPending != b.isPending) return a.isPending ? 1 : -1;
  return a.sentAt.compareTo(b.sentAt);
}

/// Highest server position in the thread (0 when none).
int lastSeqOf(List<ChatMessage> messages) => messages.fold(0, (n, m) => (m.seq ?? 0) > n ? m.seq! : n);

/// "Delivered / read up to N" applied to my messages.
List<ChatMessage> applyPeerPositions(List<ChatMessage> messages, {int? deliveredUpTo, int? readUpTo}) => [
      for (final m in messages)
        if (m.fromMe && m.seq != null && readUpTo != null && m.seq! <= readUpTo && m.status != MessageStatus.read)
          m.copyWith(status: MessageStatus.read)
        else if (m.fromMe && m.seq != null && deliveredUpTo != null && m.seq! <= deliveredUpTo && m.status == MessageStatus.sent)
          m.copyWith(status: MessageStatus.delivered)
        else
          m,
    ];
