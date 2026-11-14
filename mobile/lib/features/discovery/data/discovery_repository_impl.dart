import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/models/models.dart';
import '../../../shared/services/api_mappers.dart';
import '../../../shared/services/demo_backend.dart';
import '../domain/discovery_repository.dart';
import '../domain/swipe_use_cases.dart';

/// Server applies mutual preferences, block lists, approval status, quotas and
/// entitlements. The client only sends filters and decisions.
class ApiDiscoveryRepository implements DiscoveryRepository {
  ApiDiscoveryRepository(this._api);
  final ApiClient _api;
  final _cache = <String, UserProfile>{}; // peer data for match dialogs

  @override
  Future<List<UserProfile>> suggestions(DiscoverFilters f) => guard(() async {
        final q = <String, dynamic>{
          'limit': 10,
          'ageMin': f.ageMin,
          'ageMax': f.ageMax,
          if (f.countryIso != null) 'countryCode': f.countryIso,
          if (f.city.isNotEmpty) 'city': f.city,
          if (f.interests.isNotEmpty) 'interests': f.interests.join(','),
          if (f.maritalStatuses.isNotEmpty) 'maritalStatuses': f.maritalStatuses.map(toApiEnum).join(','),
          if (f.educations.isNotEmpty) 'educations': f.educations.map(toApiEnum).join(','),
          if (f.profession.isNotEmpty) 'occupation': f.profession,
          if (f.nationality != null) 'nationality': f.nationality,
          'sort': 'nearest',
          if (f.minCompatibility != null) 'minCompatibility': f.minCompatibility,
          if (f.height != null) ...{'heightMin': f.height!.$1, 'heightMax': f.height!.$2},
          if (f.weight != null) ...{'weightMin': f.weight!.$1, 'weightMax': f.weight!.$2},
        };
        final r = await _api.dio.get<Map<String, dynamic>>('/discovery', queryParameters: q);
        final list = (r.data!['items'] as List).map((j) => ApiMappers.profile(Map<String, dynamic>.from(j as Map))).toList();
        for (final p in list) {
          _cache[p.id] = p;
        }
        return list;
      });

  @override
  Future<MatchItem?> like(String userId, {String? compliment}) => guard(() async {
        final r = await _api.dio.post<Map<String, dynamic>>('/likes', data: {'userId': userId, if (compliment != null) 'compliment': compliment});
        if (r.data!['matched'] != true) return null;
        final peer = _cache[userId] ?? await _fetch(userId);
        return MatchItem(id: r.data!['matchId'] as String, peer: peer, createdAt: DateTime.now(), isNew: true);
      }, quota: 'likes');

  Future<UserProfile> _fetch(String id) async {
    final r = await _api.dio.get<Map<String, dynamic>>('/profiles/$id');
    return ApiMappers.profile(r.data!);
  }

  @override
  Future<void> pass(String userId) => guard(() => _api.dio.post<void>('/passes', data: {'userId': userId}));

  @override
  Future<void> undo(String userId) => guard(() => _api.dio.post<void>('/undo', data: {'userId': userId}), quota: 'undos');
}

class DemoDiscoveryRepository implements DiscoveryRepository {
  DemoDiscoveryRepository(this._b);
  final DemoBackend _b;

  @override
  Future<List<UserProfile>> suggestions(DiscoverFilters filters) => _b.discover(filters);
  @override
  Future<MatchItem?> like(String userId, {String? compliment}) => _b.like(userId, compliment: compliment);
  @override
  Future<void> pass(String userId) => _b.pass(userId);
  @override
  Future<void> undo(String userId) => _b.undo(userId);
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => useApi ? ApiDiscoveryRepository(ref.watch(apiClientProvider)) : DemoDiscoveryRepository(ref.watch(demoBackendProvider)),
);
final swipeUseCaseProvider = Provider((ref) => SwipeUseCase(ref.watch(discoveryRepositoryProvider)));
final undoUseCaseProvider = Provider((ref) => UndoUseCase(ref.watch(discoveryRepositoryProvider)));
