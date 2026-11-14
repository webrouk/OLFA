import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/discovery_repository.dart';
import '../domain/swipe_use_cases.dart';

class DemoDiscoveryRepository implements DiscoveryRepository {
  DemoDiscoveryRepository(this._b);
  final DemoBackend _b;

  @override
  Future<List<UserProfile>> suggestions(DiscoverFilters filters) => _b.discover(filters);

  @override
  Future<MatchItem?> like(String userId) => _b.like(userId);

  @override
  Future<void> pass(String userId) => _b.pass(userId);

  @override
  Future<void> undo(String userId) => _b.undo(userId);
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) => DemoDiscoveryRepository(ref.watch(demoBackendProvider)));
final swipeUseCaseProvider = Provider((ref) => SwipeUseCase(ref.watch(discoveryRepositoryProvider)));
final undoUseCaseProvider = Provider((ref) => UndoUseCase(ref.watch(discoveryRepositoryProvider)));
