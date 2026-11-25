import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/components/labels.dart';
import '../../../shared/models/models.dart';
import '../data/support_repository.dart';
import '../../../core/routing/navigation.dart';

Map<String, String> ticketCategories(AppLocalizations l) =>
    {'account': l.catAccount, 'verification': l.catVerification, 'payment': l.catPayment, 'technical': l.catTechnical, 'other': l.catOther};

String ticketStatusLabel(AppLocalizations l, TicketStatus s) => switch (s) {
      TicketStatus.open => l.ticketOpen,
      TicketStatus.pendingUser => l.ticketAwaitingYou,
      TicketStatus.resolved => l.ticketResolved,
      TicketStatus.closed => l.ticketClosed,
    };

/// 25 — Help & support: searchable FAQ (from the server, in the app language),
/// your support requests with unread replies, and a new request with attachments.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});
  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _q = '';
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final cats = ticketCategories(l);
    final tickets = ref.watch(ticketsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.screenHelp)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newTicket),
        icon: const Icon(Icons.edit_outlined),
        label: Text(l.newRequest),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ticketsProvider);
          ref.invalidate(faqProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            // ── my requests (replies arrive here) ──
            tickets.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SectionLabel(l.myRequests),
                      TileGroup(children: [
                        for (final tk in list.take(5))
                          OlfaListTile(
                            icon: tk.lastFromStaff ? Icons.support_agent_rounded : Icons.mark_chat_read_outlined,
                            accent: tk.unread > 0,
                            title: tk.subject,
                            subtitle: '${ticketStatusLabel(l, tk.status)} · ${shortTime(context, tk.lastMessageAt)}',
                            trailing: tk.unread > 0 ? OlfaTag('${tk.unread}', style: OlfaTagStyle.primary) : null,
                            onTap: () async {
                              await context.pushOnce(Routes.ticket(tk.id));
                              ref.invalidate(ticketsProvider);
                            },
                          ),
                      ]),
                      const SizedBox(height: 18),
                    ]),
            ),
            // ── FAQ ──
            SectionLabel(l.faqTitle),
            TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(hintText: l.searchHelp, prefixIcon: const Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 12),
            ChoiceWrap<String?>(
              options: [null, ...cats.keys],
              label: (k) => k == null ? l.all : cats[k]!,
              isSelected: (k) => _cat == k,
              onTap: (k) => setState(() => _cat = k),
            ),
            const SizedBox(height: 8),
            AsyncView<List<FaqEntry>>(
              value: ref.watch(faqProvider),
              onRetry: () => ref.invalidate(faqProvider),
              data: (faq) {
                final q = _q.toLowerCase();
                final list = faq.where((f) => (_cat == null || f.category == _cat) && (q.isEmpty || f.question.toLowerCase().contains(q) || f.answer.toLowerCase().contains(q))).toList();
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      Text(l.noResults, style: t.caption),
                      const SizedBox(height: 10),
                      SecondaryButton(label: l.askSupport, expand: false, onPressed: () => context.push(Routes.newTicket)),
                    ]),
                  );
                }
                return Column(children: [
                  for (final f in list)
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 14),
                        expandedAlignment: AlignmentDirectional.centerStart,
                        iconColor: OlfaColors.primary,
                        title: Text(f.question, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                        shape: const Border(bottom: BorderSide(color: OlfaColors.gray)),
                        collapsedShape: const Border(bottom: BorderSide(color: OlfaColors.gray)),
                        children: [SelectableText(f.answer, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted))],
                      ),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 22),
            InfoBanner(text: l.contactSupportBody, icon: Icons.support_agent_rounded),
          ],
        ),
      ),
    );
  }
}
