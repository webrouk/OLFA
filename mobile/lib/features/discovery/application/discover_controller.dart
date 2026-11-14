import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../data/discovery_repository_impl.dart';
import '../domain/swipe_use_cases.dart';

class DiscoverState {
  const DiscoverState({
    this.queue = const [],
    this.history = const [],
    this.inFlight = const {},
    this.lastFailure,
    this.lastMatch,
  });

  final List<UserProfile> queue; // queue.first is the visible card
  final List<({UserProfile profile, SwipeKind kind})> history; // for undo
  final Set<String> inFlight; // double-submission guard
  final Failure? lastFailure; // one-shot, cleared by the UI
  final MatchItem? lastMatch; // one-shot, cleared by the UI

  UserProfile? get current => queue.isEmpty ? null : queue.first;
  UserProfile? get next => queue.length > 1 ? queue[1] : null;

  DiscoverState copyWith({
    List<UserProfile>? queue,
    List<({UserProfile profile, SwipeKind kind})>? history,
    Set<String>? inFlight,
    Failure? Function()? lastFailure,
    MatchItem? Function()? lastMatch,
  }) =>
      DiscoverState(
        queue: queue ?? this.queue,
        history: history ?? this.history,
        inFlight: inFlight ?? this.inFlight,
        lastFailure: lastFailure != null ? lastFailure() : this.lastFailure,
        lastMatch: lastMatch != null ? lastMatch() : this.lastMatch,
      );
}

/// Active filters for discovery. Applying them reloads the queue; the server
/// rejects paid filters for free plans (see [EntitlementRequiredFailure]).
class FiltersController extends Notifier<DiscoverFilters> {
  @override
  DiscoverFilters build() => const DiscoverFilters();
  void set(DiscoverFilters f) => state = f;
  void reset() => state = const DiscoverFilters();
}

final filtersProvider = NotifierProvider<FiltersController, DiscoverFilters>(FiltersController.new);

class DiscoverController extends AsyncNotifier<DiscoverState> {
  final _seen = <String>{};

  @override
  Future<DiscoverState> build() async {
    final filters = ref.watch(filtersProvider);
    _seen.clear();
    final list = await ref.read(discoveryRepositoryProvider).suggestions(filters);
    return DiscoverState(queue: _dedupe(list));
  }

  List<UserProfile> _dedupe(List<UserProfile> l) => [for (final p in l) if (_seen.add(p.id)) p];

  /// Optimistic swipe: the card leaves immediately; on failure it returns to
  /// the top of the queue and the failure is surfaced once.
  Future<void> swipe(SwipeKind kind) async {
    final s = state.valueOrNull;
    final p = s?.current;
    if (s == null || p == null || s.inFlight.contains(p.id)) return;
    final ent = ref.read(entitlementsProvider).valueOrNull;
    if (kind == SwipeKind.like && ent != null && ent.likesLeft <= 0) {
      state = AsyncData(s.copyWith(lastFailure: () => const QuotaExceededFailure('likes')));
      return;
    }

    state = AsyncData(s.copyWith(
      queue: s.queue.sublist(1),
      inFlight: {...s.inFlight, p.id},
      history: [...s.history, (profile: p, kind: kind)],
    ));
    if (kind == SwipeKind.like) {
      ref.read(entitlementsProvider.notifier).applyLocal((e) => e.copyWith(likesUsed: e.likesUsed + 1));
    }
    _prefetchIfLow();

    try {
      final match = await ref.read(swipeUseCaseProvider).call(kind, p.id, ent ?? _fallbackEnt());
      final cur = state.valueOrNull!;
      state = AsyncData(cur.copyWith(inFlight: {...cur.inFlight}..remove(p.id), lastMatch: match == null ? null : () => match));
    } on AlreadyActedFailure {
      final cur = state.valueOrNull!;
      state = AsyncData(cur.copyWith(inFlight: {...cur.inFlight}..remove(p.id)));
    } on Failure catch (f) {
      final cur = state.valueOrNull!;
      state = AsyncData(cur.copyWith(
        queue: [p, ...cur.queue],
        inFlight: {...cur.inFlight}..remove(p.id),
        history: [...cur.history]..removeWhere((h) => h.profile.id == p.id),
        lastFailure: () => f,
      ));
      if (kind == SwipeKind.like) ref.read(entitlementsProvider.notifier).refresh();
    }
  }

  Future<void> undo() async {
    final s = state.valueOrNull;
    if (s == null || s.history.isEmpty) return;
    final last = s.history.last;
    final ent = ref.read(entitlementsProvider).valueOrNull ?? _fallbackEnt();
    try {
      await ref.read(undoUseCaseProvider).call(last.profile.id, ent);
      final cur = state.valueOrNull!;
      state = AsyncData(cur.copyWith(queue: [last.profile, ...cur.queue], history: [...cur.history]..removeLast()));
      await ref.read(entitlementsProvider.notifier).refresh();
    } on Failure catch (f) {
      state = AsyncData(state.valueOrNull!.copyWith(lastFailure: () => f));
    }
  }

  void clearEvents() {
    final s = state.valueOrNull;
    if (s != null) state = AsyncData(s.copyWith(lastFailure: () => null, lastMatch: () => null));
  }

  Future<void> _prefetchIfLow() async {
    final s = state.valueOrNull;
    if (s == null || s.queue.length > 2) return;
    try {
      final more = await ref.read(discoveryRepositoryProvider).suggestions(ref.read(filtersProvider));
      final cur = state.valueOrNull;
      if (cur != null) state = AsyncData(cur.copyWith(queue: [...cur.queue, ..._dedupe(more)]));
    } on Failure {
      // Silent: the empty state offers a retry.
    }
  }

  Entitlements _fallbackEnt() => const Entitlements(
        plan: PlanCode.free, dailyLikes: 1, likesUsed: 0, dailyMessages: 0, messagesUsed: 0,
        dailyUndos: 0, undosUsed: 0, advancedFilters: false, seeWhoLikedYou: false, incognito: false,
      );
}

final discoverControllerProvider = AsyncNotifierProvider<DiscoverController, DiscoverState>(DiscoverController.new);
