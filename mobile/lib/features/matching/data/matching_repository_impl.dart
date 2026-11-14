import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/matching_repository.dart';

class DemoMatchingRepository implements MatchingRepository {
  DemoMatchingRepository(this._b);
  final DemoBackend _b;

  @override
  Future<List<MatchItem>> matches() => _b.matches();

  @override
  Future<String> startConversation(String matchId) => _b.startConversation(matchId);

  @override
  Future<({int count, List<UserProfile> profiles})> likesReceived() => _b.likesReceived();
}

final matchingRepositoryProvider = Provider<MatchingRepository>((ref) => DemoMatchingRepository(ref.watch(demoBackendProvider)));

final matchesProvider = FutureProvider<List<MatchItem>>((ref) => ref.watch(matchingRepositoryProvider).matches());

final likesReceivedProvider =
    FutureProvider<({int count, List<UserProfile> profiles})>((ref) => ref.watch(matchingRepositoryProvider).likesReceived());
