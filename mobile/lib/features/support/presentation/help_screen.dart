import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../data/support_repository.dart';

/// 25 — FAQ & Help center with search, categories and a support ticket form.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});
  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _q = '';
  String? _cat;
  String _ticketCat = 'account';
  final _msg = TextEditingController();
  bool _sending = false;
  String? _ticketNo;
  String? _msgError;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    if (_msg.text.trim().length < 10) {
      setState(() => _msgError = l.errorMessageShort);
      return;
    }
    setState(() {
      _sending = true;
      _msgError = null;
    });
    try {
      final no = await ref.read(supportRepositoryProvider).submitTicket(_ticketCat, _msg.text);
      if (mounted) setState(() => _ticketNo = no);
    } catch (e) {
      if (mounted) showToast(context, failureMessage(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final cats = {'account': l.catAccount, 'verification': l.catVerification, 'payment': l.catPayment, 'technical': l.catTechnical};

    return Scaffold(
      appBar: AppBar(title: Text(l.screenHelp)),
      body: AsyncView<List<FaqEntry>>(
        value: ref.watch(faqProvider),
        onRetry: () => ref.invalidate(faqProvider),
        data: (faq) {
          final list = faq.where((f) => (_cat == null || f.category == _cat) && (_q.isEmpty || f.question.toLowerCase().contains(_q.toLowerCase()) || f.answer.toLowerCase().contains(_q.toLowerCase()))).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
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
              if (list.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(l.noResults, style: t.caption)))
              else
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
                      children: [Text(f.answer, style: t.bodyMedium.copyWith(color: OlfaColors.textMuted))],
                    ),
                  ),
              const SizedBox(height: 22),
              OlfaCard(
                padding: const EdgeInsets.all(18),
                child: _ticketNo != null
                    ? Row(children: [
                        const Icon(Icons.check_circle_outline_rounded, color: OlfaColors.primary, size: 26),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l.ticketCreated(_ticketNo!), style: t.bodyMedium)),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.contactSupport, style: t.h3),
                        const SizedBox(height: 4),
                        Text(l.contactSupportBody, style: t.caption),
                        const SizedBox(height: 14),
                        Text(l.category, style: t.inputLabel),
                        const SizedBox(height: 8),
                        ChoiceWrap<String>(options: cats.keys.toList(), label: (k) => cats[k]!, isSelected: (k) => _ticketCat == k, onTap: (k) => setState(() => _ticketCat = k)),
                        const SizedBox(height: 16),
                        OlfaTextField(label: l.message, controller: _msg, maxLines: 4, maxLength: 2000, error: _msgError),
                        PrimaryButton(label: l.send, loading: _sending, onPressed: _send),
                      ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
