import '../../../shared/models/models.dart';

abstract interface class DiscoveryRepository {
  /// Server applies mutual preferences, block lists, account status and
  /// entitlement checks; the client only sends the requested filters.
  Future<List<UserProfile>> suggestions(DiscoverFilters filters);

  /// Returns a match when the like is mutual.
  /// [compliment] travels with the like (monthly quota) and is shown first.
  Future<MatchItem?> like(String userId, {String? compliment});
  Future<void> pass(String userId);
  Future<void> undo(String userId);
}
