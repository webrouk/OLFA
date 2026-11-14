import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/matching_repository.dart';

class ApiMatchingRepository implements MatchingRepository {
  ApiMatchingRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<MatchItem>> matches() => guard(() async {
        final r = await _api.dio.get<List<dynamic>>('/matches');
        return r.data!.map((x) {
          final j = Map<String, dynamic>.from(x as Map);
          return MatchItem(
            id: j['id'] as String,
            peer: ApiMappers.profile(Map<String, dynamic>.from(j['peer'] as Map)),
            createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
            conversationId: j['conversationId'] as String?,
            isNew: j['conversationId'] == null,
          );
        }).toList();
      });

  @override
  Future<String> startConversation(String matchId) => guard(() async {
        final r = await _api.dio.post<Map<String, dynamic>>('/matches/$matchId/conversation');
        return r.data!['conversationId'] as String;
      }, quota: 'messages');

  @override
  Future<({int count, List<UserProfile> profiles})> likesReceived() => guard(() async {
        final r = await _api.dio.get<Map<String, dynamic>>('/likes/received');
        final profiles = (r.data!['profiles'] as List).map((j) => ApiMappers.profile(Map<String, dynamic>.from(j as Map))).toList();
        return (count: (r.data!['count'] as num).toInt(), profiles: profiles);
      });
}

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

final matchingRepositoryProvider = Provider<MatchingRepository>(
  (ref) => useApi ? ApiMatchingRepository(ref.watch(apiClientProvider)) : DemoMatchingRepository(ref.watch(demoBackendProvider)),
);

final matchesProvider = FutureProvider<List<MatchItem>>((ref) => ref.watch(matchingRepositoryProvider).matches());

final likesReceivedProvider =
    FutureProvider<({int count, List<UserProfile> profiles})>((ref) => ref.watch(matchingRepositoryProvider).likesReceived());
