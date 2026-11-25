import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/cache_for.dart';
import '../../../shared/models/models.dart';
import '../data/consultations_repository_impl.dart';
import '../domain/consultations_repository.dart';

class CounselorQueryController extends Notifier<CounselorQuery> {
  @override
  CounselorQuery build() => const CounselorQuery();
  void set(CounselorQuery q) => state = q;
}

final counselorQueryProvider = NotifierProvider<CounselorQueryController, CounselorQuery>(CounselorQueryController.new);

/// One cached result per filter combination: going back to a filter is instant.
final counselorsByQueryProvider = FutureProvider.autoDispose.family<List<Counselor>, CounselorQuery>((ref, q) {
  ref.cacheFor(CacheTtl.list);
  return ref.watch(consultationsRepositoryProvider).counselors(q);
});

final counselorsProvider = FutureProvider.autoDispose<List<Counselor>>(
  (ref) => ref.watch(counselorsByQueryProvider(ref.watch(counselorQueryProvider)).future),
);

final counselorProvider = FutureProvider.autoDispose.family<Counselor, String>((ref, id) {
  ref.cacheFor(CacheTtl.detail);
  return ref.watch(consultationsRepositoryProvider).counselor(id);
});

final myConsultationsProvider = FutureProvider.autoDispose<List<Consultation>>((ref) => ref.watch(consultationsRepositoryProvider).mine());

/// Null when the user has not applied as a counselor.
final myCounselorProvider = FutureProvider.autoDispose<Counselor?>((ref) => ref.watch(consultationsRepositoryProvider).myCounselorProfile());

/// Completed sessions the client still has to review (gates new bookings).
final pendingReviewsProvider = FutureProvider.autoDispose<List<PendingReview>>((ref) => ref.watch(consultationsRepositoryProvider).pendingReviews());

final integrityCaseProvider = FutureProvider.autoDispose<IntegrityCase?>((ref) => ref.watch(consultationsRepositoryProvider).integrityCase());

final counselorDeskProvider = FutureProvider.autoDispose<List<Consultation>>((ref) => ref.watch(consultationsRepositoryProvider).desk());

/// Bookable times for (counselorId, offeringId).
final slotsProvider = FutureProvider.autoDispose.family<SlotList, (String, String)>((ref, k) => ref.watch(consultationsRepositoryProvider).slots(k.$1, k.$2));

final myScheduleProvider = FutureProvider.autoDispose<CounselorSchedule>((ref) => ref.watch(consultationsRepositoryProvider).mySchedule());
final myReviewsProvider = FutureProvider.autoDispose<MyReviews>((ref) => ref.watch(consultationsRepositoryProvider).myReviews());
