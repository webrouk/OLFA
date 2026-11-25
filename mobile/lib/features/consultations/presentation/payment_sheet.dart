import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/localization/generated/app_localizations.dart';
import '../../../core/theme/olfa_colors.dart';
import '../../../core/theme/olfa_spacing.dart';
import '../../../core/theme/olfa_typography.dart';
import '../../../core/widgets/olfa_widgets.dart';
import '../../../shared/models/models.dart';
import '../application/consultation_providers.dart';
import '../data/consultations_repository_impl.dart';
import 'consult_labels.dart';

/// What the sheet ended with.
sealed class PayOutcome {
  const PayOutcome();
}

/// Paid: the booking waits for the counselor's confirmation.
class PayDone extends PayOutcome {
  const PayDone(this.consultationId);
  final String consultationId;
}

/// Closed without paying (the booking, if created, stays until its window ends).
class PayClosed extends PayOutcome {
  const PayClosed();
}

/// Creating the booking itself failed (slot taken, open booking, review required…):
/// the booking page handles it.
class PayBookingFailed extends PayOutcome {
  const PayBookingFailed(this.failure);
  final Failure failure;
}

/// The summary a payment sheet shows.
class PaySummary {
  const PaySummary({required this.counselorName, this.kind, required this.details, required this.amountMinor, required this.currency, this.when});
  final String counselorName;
  final CounselorKind? kind;
  final String details;
  final DateTime? when;
  final int amountMinor;
  final String currency;
}

/// Payment as a bottom sheet over the booking (no extra page): what you pay
/// for, the price, the method, then the result. A declined card or a closed
/// payment form keeps the booking and its time; "Try again" pays the same
/// booking ([ConsultationsRepository.retryPayment]).
///
/// [createBooking] runs once, the first time "Pay" is pressed; pass
/// [existingBookingId] instead to pay a booking that already exists.
Future<PayOutcome> showPaymentSheet(
  BuildContext context, {
  required PaySummary summary,
  Future<BookingIntent> Function()? createBooking,
  String? existingBookingId,
}) async {
  final r = await showModalBottomSheet<PayOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: OlfaColors.white,
    isDismissible: true,
    builder: (_) => _PaymentSheet(summary: summary, createBooking: createBooking, existingBookingId: existingBookingId),
  );
  return r ?? const PayClosed();
}

enum _Phase { review, processing, success, failed, cancelled }

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.summary, this.createBooking, this.existingBookingId});
  final PaySummary summary;
  final Future<BookingIntent> Function()? createBooking;
  final String? existingBookingId;
  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  _Phase _phase = _Phase.review;
  String? _bookingId;
  DateTime? _keptUntil;

  @override
  void initState() {
    super.initState();
    _bookingId = widget.existingBookingId;
  }

  Future<void> _pay() async {
    final repo = ref.read(consultationsRepositoryProvider);
    setState(() => _phase = _Phase.processing);
    BookingIntent intent;
    try {
      if (_bookingId == null) {
        intent = await widget.createBooking!();
        _bookingId = intent.consultationId;
      } else {
        intent = await repo.retryPayment(_bookingId!);
      }
      _keptUntil = intent.expiresAt;
    } on Failure catch (e) {
      if (!mounted) return;
      if (_bookingId == null) {
        Navigator.of(context).pop(PayBookingFailed(e)); // nothing was created: the booking page explains
      } else {
        setState(() => _phase = _Phase.failed);
        showToast(context, e is ServerFailure && e.code == 'invalid_state' ? AppLocalizations.of(context).payWindowClosed : failureMessage(context, e));
      }
      return;
    }
    try {
      await repo.pay(intent);
      ref.invalidate(myConsultationsProvider);
      if (mounted) setState(() => _phase = _Phase.success);
    } on ServerFailure catch (e) {
      ref.invalidate(myConsultationsProvider);
      if (mounted) setState(() => _phase = e.code == 'payment_cancelled' ? _Phase.cancelled : _Phase.failed);
    } on Failure catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.type;
    final s = widget.summary;
    final lang = Localizations.localeOf(context).languageCode;
    final price = money(context, s.amountMinor, s.currency);
    final busy = _phase == _Phase.processing;
    return PopScope(
      canPop: !busy, // never close the sheet in the middle of a payment
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: switch (_phase) {
            _Phase.success => _Result(
                icon: Icons.check_circle_rounded,
                title: l.paySuccessTitle,
                body: l.paySuccessBody,
                actions: [PrimaryButton(label: l.payViewConsultations, onPressed: () => Navigator.of(context).pop(PayDone(_bookingId!)))],
              ),
            _Phase.failed || _Phase.cancelled => _Result(
                icon: _phase == _Phase.cancelled ? Icons.cancel_outlined : Icons.error_outline_rounded,
                title: _phase == _Phase.cancelled ? l.payCancelledTitle : l.payFailedTitle,
                body: _keptUntil == null ? l.paymentFailed : l.payKeptUntil(DateFormat.Hm(lang).format(_keptUntil!)),
                actions: [
                  PrimaryButton(label: l.retry, icon: Icons.refresh_rounded, onPressed: _pay),
                  const SizedBox(height: 8),
                  SecondaryButton(label: l.payViewConsultations, onPressed: () => Navigator.of(context).pop(const PayClosed())),
                ],
              ),
            _ => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.paySheetTitle, style: t.h3),
                const SizedBox(height: 14),
                OlfaCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CounselorAvatar(size: 40, name: s.counselorName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.counselorName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                          if (s.kind != null) Text(kindLabel(l, s.kind!), style: t.caption),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Text(s.details, style: t.bodySmall),
                    if (s.when != null) Text(DateFormat.yMMMMEEEEd(lang).add_Hm().format(s.when!), style: t.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 14),
                Text(l.payMethodTitle, style: t.inputLabel),
                const SizedBox(height: 8),
                OlfaCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  borderColor: OlfaColors.primary,
                  child: Row(children: [
                    const Icon(Icons.credit_card_rounded, color: OlfaColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.payMethodCard, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                        Text(l.payMethodCardSub, style: t.caption),
                      ]),
                    ),
                    const Icon(Icons.radio_button_checked_rounded, color: OlfaColors.primary, size: 20),
                  ]),
                ),
                const SizedBox(height: 12),
                InfoBanner(icon: Icons.shield_outlined, text: l.payBeforeConfirmNote),
                const SizedBox(height: 14),
                Row(children: [
                  Text(l.total, style: t.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(price, style: t.h3),
                ]),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: busy ? l.payProcessing : l.payNowAmount(price),
                  icon: Icons.lock_outline_rounded,
                  loading: busy,
                  onPressed: busy ? null : _pay,
                ),
              ]),
          },
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.icon, required this.title, required this.body, required this.actions});
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Semantics(
      liveRegion: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 4),
        Icon(icon, size: 56, color: OlfaColors.primary),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: t.h3),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: t.bodyMedium),
        const SizedBox(height: 20),
        ...actions,
        const SizedBox(height: OlfaSpace.xs),
      ]),
    );
  }
}
