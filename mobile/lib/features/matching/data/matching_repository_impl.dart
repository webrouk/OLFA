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
            paused: j['paused'] == true,
          );
        }).toList();
      });

  @override
  Future<String> startConversation(String matchId) => guard(() async {
        final r = await _api.dio.post<Map<String, dynamic>>('/matches/$matchId/conversation');
        return r.data!['conversationId'] as String;
      }, quota: 'messages');

  @override
  Future<LikesInbox> likesReceived({String? cursor}) => guard(() async {
        final r = await _api.dio.get<Map<String, dynamic>>('/likes/received', queryParameters: {if (cursor != null) 'cursor': cursor});
        ReceivedLike one(dynamic x) {
          final j = Map<String, dynamic>.from(x as Map);
          return ReceivedLike(profile: ApiMappers.profile(Map<String, dynamic>.from(j['profile'] as Map)), at: DateTime.parse(j['at'] as String).toLocal(), compliment: j['compliment'] as String?);
        }
        final d = r.data!;
        return LikesInbox(
          count: (d['count'] as num).toInt(),
          compliments: (d['compliments'] as List? ?? const []).map(one).toList(),
          items: (d['items'] as List? ?? const []).map(one).toList(),
          locked: d['locked'] == true,
          nextCursor: d['nextCursor'] as String?,
        );
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
  Future<LikesInbox> likesReceived({String? cursor}) => _b.likesReceived();
}

final matchingRepositoryProvider = Provider<MatchingRepository>(
  (ref) => useApi ? ApiMatchingRepository(ref.watch(apiClientProvider)) : DemoMatchingRepository(ref.watch(demoBackendProvider)),
);

final matchesProvider = FutureProvider<List<MatchItem>>((ref) => ref.watch(matchingRepositoryProvider).matches());

final likesReceivedProvider = FutureProvider<LikesInbox>((ref) => ref.watch(matchingRepositoryProvider).likesReceived());
