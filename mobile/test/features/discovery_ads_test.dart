import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olfa/features/ads/application/discovery_ads_controller.dart';
import 'package:olfa/features/ads/data/native_ad_gateway.dart';
import 'package:olfa/features/ads/domain/ad_schedule.dart';
import 'package:olfa/shared/models/models.dart';
import 'package:olfa/shared/services/api_mappers.dart';

class FakeAd implements LoadedNativeAd {
  FakeAd([DateTime? at]) : loadedAt = at ?? DateTime.now();
  @override
  final DateTime loadedAt;
  bool disposed = false;
  @override
  Widget view() => const SizedBox();
  @override
  void dispose() => disposed = true;
}

class FakeGateway implements NativeAdGateway {
  int loads = 0;
  bool fill = true;
  final created = <FakeAd>[];
  Completer<void>? gate;
  @override
  Future<bool> prepare(DiscoveryAds config) async => true;
  @override
  Future<LoadedNativeAd?> load(DiscoveryAds config) async {
    loads++;
    if (gate != null) await gate!.future;
    if (!fill) return null;
    final a = FakeAd();
    created.add(a);
    return a;
  }
}

const cfg = DiscoveryAds(enabled: true, firstAfter: 4, interval: 6, maxPerSession: 2, preloadAhead: 2, androidUnitId: 'ca-app-pub-1234567890123456/1234567890');

final configState = StateProvider<DiscoveryAds>((ref) => cfg);

ProviderContainer make(FakeGateway g) => ProviderContainer(overrides: [
      nativeAdGatewayProvider.overrideWithValue(g),
      discoveryAdsConfigProvider.overrideWith((ref) => ref.watch(configState)),
    ]);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('AdSchedule', () {
    test('first after N, then every interval, capped', () {
      expect(AdSchedule.isDue(cfg, decided: 3, used: 0), isFalse);
      expect(AdSchedule.isDue(cfg, decided: 4, used: 0), isTrue);
      expect(AdSchedule.isDue(cfg, decided: 9, used: 1), isFalse);
      expect(AdSchedule.isDue(cfg, decided: 10, used: 1), isTrue);
      expect(AdSchedule.isDue(cfg, decided: 99, used: 2), isFalse);
      expect(AdSchedule.isDue(DiscoveryAds.off, decided: 99, used: 0), isFalse);
    });
    test('preload starts only near the slot (lazy)', () {
      expect(AdSchedule.shouldPreload(cfg, decided: 1, used: 0), isFalse);
      expect(AdSchedule.shouldPreload(cfg, decided: 2, used: 0), isTrue);
    });
  });

  group('server payload', () {
    test('paid plans never get ads, even if the server says so', () {
      final on = {'enabled': true, 'units': {'android': 'x', 'ios': 'y'}};
      expect(ApiMappers.discoveryAds(on, 'PREMIUM').enabled, isFalse);
      expect(ApiMappers.discoveryAds(on, 'PLUS').enabled, isFalse);
      expect(ApiMappers.discoveryAds(on, 'FREE').enabled, isTrue);
      expect(ApiMappers.discoveryAds(null, 'FREE').enabled, isFalse);
      expect(ApiMappers.discoveryAds({'enabled': 'true'}, 'FREE').enabled, isFalse);
    });
  });

  group('DiscoveryAdsController', () {
    test('loads lazily, shows at the slot, one load per ad (no reloads)', () async {
      final g = FakeGateway();
      final c = make(g);
      addTearDown(c.dispose);
      final n = c.read(discoveryAdsProvider.notifier);
      n.onProfileDecided();
      await settle();
      expect(g.loads, 0, reason: 'too early to load');
      n.onProfileDecided(); // 2 → preload window
      await settle();
      expect(g.loads, 1);
      expect(c.read(discoveryAdsProvider).showing, isFalse);
      n.onProfileDecided(); // 3
      await settle();
      expect(g.loads, 1, reason: 'the loaded ad is kept, not reloaded');
      n.onProfileDecided(); // 4 → due
      expect(c.read(discoveryAdsProvider).showing, isTrue);
      n.dismiss();
      final s = c.read(discoveryAdsProvider);
      expect(s.showing, isFalse);
      expect(s.used, 1);
      expect(g.created.single.disposed, isTrue);
    });

    test('no fill skips the slot without retrying', () async {
      final g = FakeGateway()..fill = false;
      final c = make(g);
      addTearDown(c.dispose);
      final n = c.read(discoveryAdsProvider.notifier);
      for (var i = 0; i < 4; i++) {
        n.onProfileDecided();
        await settle();
      }
      expect(c.read(discoveryAdsProvider).showing, isFalse);
      expect(c.read(discoveryAdsProvider).used, 1);
      expect(g.loads, 1);
    });

    test('upgrading drops the ad, including one still loading', () async {
      final g = FakeGateway()..gate = Completer<void>();
      final c = make(g);
      addTearDown(c.dispose);
      c.listen(discoveryAdsProvider, (_, __) {});
      final n = c.read(discoveryAdsProvider.notifier);
      n.onProfileDecided();
      n.onProfileDecided();
      await settle();
      expect(g.loads, 1);
      c.read(configState.notifier).state = DiscoveryAds.off; // e.g. bought Plus
      await settle();
      g.gate!.complete();
      await settle();
      expect(g.created.single.disposed, isTrue);
      final s = c.read(discoveryAdsProvider);
      expect(s.ad, isNull);
      c.read(discoveryAdsProvider.notifier).onProfileDecided();
      expect(c.read(discoveryAdsProvider).decided, 0, reason: 'ads off: nothing is counted');
    });

    test('a stale ad (over 55 min) is not shown', () async {
      final g = FakeGateway();
      final c = make(g);
      addTearDown(c.dispose);
      final n = c.read(discoveryAdsProvider.notifier);
      n.onProfileDecided();
      n.onProfileDecided();
      await settle();
      // replace with an old ad
      final old = FakeAd(DateTime.now().subtract(const Duration(hours: 2)));
      n.state = n.state.copyWith(ad: old);
      n.onProfileDecided();
      n.onProfileDecided(); // due, but stale
      expect(c.read(discoveryAdsProvider).showing, isFalse);
      expect(old.disposed, isTrue);
    });
  });
}
