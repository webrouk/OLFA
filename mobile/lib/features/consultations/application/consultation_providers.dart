import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../data/consultations_repository_impl.dart';
import '../domain/consultations_repository.dart';

class CounselorQueryController extends Notifier<CounselorQuery> {
  @override
  CounselorQuery build() => const CounselorQuery();
  void set(CounselorQuery q) => state = q;
}

final counselorQueryProvider = NotifierProvider<CounselorQueryController, CounselorQuery>(CounselorQueryController.new);

final counselorsProvider = FutureProvider.autoDispose<List<Counselor>>(
  (ref) => ref.watch(consultationsRepositoryProvider).counselors(ref.watch(counselorQueryProvider)),
);

final counselorProvider = FutureProvider.autoDispose.family<Counselor, String>((ref, id) => ref.watch(consultationsRepositoryProvider).counselor(id));

final myConsultationsProvider = FutureProvider.autoDispose<List<Consultation>>((ref) => ref.watch(consultationsRepositoryProvider).mine());

/// Null when the user has not applied as a counselor.
final myCounselorProvider = FutureProvider.autoDispose<Counselor?>((ref) => ref.watch(consultationsRepositoryProvider).myCounselorProfile());

/// Completed sessions the client still has to review (gates new bookings).
final pendingReviewsProvider = FutureProvider.autoDispose<List<PendingReview>>((ref) => ref.watch(consultationsRepositoryProvider).pendingReviews());

final integrityCaseProvider = FutureProvider.autoDispose<IntegrityCase?>((ref) => ref.watch(consultationsRepositoryProvider).integrityCase());

final counselorDeskProvider = FutureProvider.autoDispose<List<Consultation>>((ref) => ref.watch(consultationsRepositoryProvider).desk());
