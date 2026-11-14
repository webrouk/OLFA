import '../../../core/errors/failure.dart';
import '../../../shared/models/models.dart';
import 'discovery_repository.dart';

enum SwipeKind { like, pass }

/// Validates a swipe against the known entitlements before hitting the
/// network (fast feedback), then defers to the server as the source of truth.
class SwipeUseCase {
  const SwipeUseCase(this._repo);
  final DiscoveryRepository _repo;

  Future<MatchItem?> call(SwipeKind kind, String userId, Entitlements e) async {
    if (kind == SwipeKind.like) {
      if (e.likesLeft <= 0) throw const QuotaExceededFailure('likes');
      return _repo.like(userId);
    }
    await _repo.pass(userId);
    return null;
  }
}

class UndoUseCase {
  const UndoUseCase(this._repo);
  final DiscoveryRepository _repo;

  Future<void> call(String userId, Entitlements e) {
    if (e.undosLeft <= 0) throw const QuotaExceededFailure('undos');
    return _repo.undo(userId);
  }
}
