import '../../../shared/models/models.dart';

abstract interface class DiscoveryRepository {
  /// Server applies mutual preferences, block lists, account status and
  /// entitlement checks; the client only sends the requested filters.
  Future<List<UserProfile>> suggestions(DiscoverFilters filters);

  /// Returns a match when the like is mutual.
  Future<MatchItem?> like(String userId);
  Future<void> pass(String userId);
  Future<void> undo(String userId);
}
