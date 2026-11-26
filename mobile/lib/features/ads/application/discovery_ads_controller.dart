import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../subscriptions/application/entitlements_controller.dart';
import '../data/native_ad_gateway.dart';
import '../domain/ad_schedule.dart';

/// Discovery ad slot for this session.
class DiscoveryAdsState {
  const DiscoveryAdsState({this.decided = 0, this.used = 0, this.ad, this.showing = false, this.loading = false});

  /// Profiles liked or passed since the app session started.
  final int decided;

  /// Ad slots used (shown, or skipped because no ad was available).
  final int used;

  /// The next ad, loaded ahead of time (lazy: only near its slot).
  final LoadedNativeAd? ad;

  /// The ad card is on screen in place of the next profile.
  final bool showing;
  final bool loading;

  DiscoveryAdsState copyWith({int? decided, int? used, LoadedNativeAd? ad, bool clearAd = false, bool? showing, bool? loading}) => DiscoveryAdsState(
        decided: decided ?? this.decided,
        used: used ?? this.used,
        ad: clearAd ? null : (ad ?? this.ad),
        showing: showing ?? this.showing,
        loading: loading ?? this.loading,
      );
}

/// The member's ad settings: Free plan only — a paid plan is never shown ads,
/// even if the server sent something unexpected.
final discoveryAdsConfigProvider = Provider<DiscoveryAds>((ref) {
  final e = ref.watch(entitlementsProvider.select((s) => s.valueOrNull));
  if (e == null || e.plan != PlanCode.free || !e.ads.enabled) return DiscoveryAds.off;
  return e.ads;
});

/// Owns the loaded ad, so scrolling, rebuilds and tab switches never reload it.
/// Rebuilt (and its ad disposed) when the settings change, e.g. after upgrading.
class DiscoveryAdsController extends Notifier<DiscoveryAdsState> {
  late DiscoveryAds _config;
  int _generation = 0;

  /// The ad this controller owns (mirrors state.ad) — disposed with the controller.
  LoadedNativeAd? _owned;

  @override
  DiscoveryAdsState build() {
    _config = ref.watch(discoveryAdsConfigProvider);
    final gen = ++_generation;
    ref.onDispose(() {
      if (gen == _generation) _generation++; // late loads from this config are dropped
      _owned?.dispose();
      _owned = null;
    });
    return const DiscoveryAdsState();
  }

  /// Call after a profile was liked or passed (not after undo).
  void onProfileDecided() {
    if (!_config.enabled) return;
    var s = state.copyWith(decided: state.decided + 1);
    // An ad is shown only at a card boundary, never popped over a profile being viewed.
    if (!s.showing && s.ad != null && AdSchedule.isDue(_config, decided: s.decided, used: s.used)) {
      if (DateTime.now().difference(s.ad!.loadedAt) < AdSchedule.maxAge) {
        s = s.copyWith(showing: true);
      } else {
        s.ad!.dispose();
        _owned = null;
        s = s.copyWith(clearAd: true);
      }
    }
    state = s;
    _preloadIfNear();
  }

  /// The member moved past the ad card ("Continue").
  void dismiss() {
    if (!state.showing) return;
    state.ad?.dispose();
    _owned = null;
    state = state.copyWith(showing: false, clearAd: true, used: state.used + 1);
    _preloadIfNear();
  }

  void _preloadIfNear() {
    final s = state;
    if (s.ad != null || s.loading || !AdSchedule.shouldPreload(_config, decided: s.decided, used: s.used)) return;
    state = s.copyWith(loading: true);
    final gen = _generation;
    final config = _config;
    unawaited(ref.read(nativeAdGatewayProvider).load(config).then((ad) {
      if (gen != _generation) {
        ad?.dispose(); // settings changed (e.g. upgraded) while loading
        return;
      }
      if (ad == null) {
        // No fill / no consent / error: skip this slot instead of retrying in a loop.
        state = state.copyWith(loading: false, used: state.used + 1);
      } else {
        _owned = ad;
        state = state.copyWith(loading: false, ad: ad);
      }
    }));
  }
}

final discoveryAdsProvider = NotifierProvider<DiscoveryAdsController, DiscoveryAdsState>(DiscoveryAdsController.new);
