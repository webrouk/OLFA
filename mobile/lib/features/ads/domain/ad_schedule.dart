import '../../../shared/models/models.dart';

/// When the Discovery ad cards appear — pure, so it is tested without the SDK.
/// Mirrors `adDue` in backend/src/domain/ads.ts.
///
/// The first ad comes after [DiscoveryAds.firstAfter] profiles (liked or
/// passed) in this session, then one every [DiscoveryAds.interval] profiles,
/// at most [DiscoveryAds.maxPerSession]. A slot whose ad fails to load is
/// skipped (counted as used), so a failing network never causes a retry loop.
abstract final class AdSchedule {
  /// Profiles decided before slot number [slot] (0-based) is due.
  static int dueAt(DiscoveryAds c, int slot) => c.firstAfter + slot * c.interval;

  static bool hasSlotsLeft(DiscoveryAds c, int used) => c.enabled && used < c.maxPerSession;

  /// An ad card is due now.
  static bool isDue(DiscoveryAds c, {required int decided, required int used}) => hasSlotsLeft(c, used) && decided >= dueAt(c, used);

  /// Close enough to the next slot to start loading its ad (lazy: never earlier).
  static bool shouldPreload(DiscoveryAds c, {required int decided, required int used}) =>
      hasSlotsLeft(c, used) && decided >= dueAt(c, used) - c.preloadAhead;

  /// AdMob native ads must be shown within an hour of loading; reload before that.
  static const maxAge = Duration(minutes: 55);
}
