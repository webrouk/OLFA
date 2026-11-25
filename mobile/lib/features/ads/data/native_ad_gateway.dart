import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/theme/olfa_colors.dart';
import '../../../shared/models/models.dart';

/// One loaded native ad, owned by the Discovery ads controller (not by a
/// widget), so rebuilds and tab switches never reload it.
abstract interface class LoadedNativeAd {
  DateTime get loadedAt;

  /// The platform ad view. Must be in the tree at most once.
  Widget view();
  void dispose();
}

/// The only place that talks to the ad SDK. Tests use a fake.
abstract interface class NativeAdGateway {
  /// Starts the SDK and asks for consent where the law requires it (UMP).
  /// Returns whether ads may be requested. Called only for Free members with
  /// ads switched on, so paid members never start the ad SDK at all.
  Future<bool> prepare(DiscoveryAds config);

  /// Loads one native ad; null when there is no fill or an error.
  Future<LoadedNativeAd?> load(DiscoveryAds config);
}

final nativeAdGatewayProvider = Provider<NativeAdGateway>((ref) => AdMobNativeAdGateway());

/// Google AdMob native ads, styled with OLFA's colours via the native template.
/// Nothing about the member (age, gender, religion, location, interests) is
/// passed to the ad request.
class AdMobNativeAdGateway implements NativeAdGateway {
  Future<bool>? _ready;

  @override
  Future<bool> prepare(DiscoveryAds config) => _ready ??= _prepare(config).catchError((Object e, StackTrace s) {
        debugPrint('ads: prepare failed: $e');
        _ready = null; // try again next session
        return false;
      });

  Future<bool> _prepare(DiscoveryAds config) async {
    // Consent first (EEA/UK and other regulated regions); outside them this is a no-op.
    final consent = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) => consent.complete()),
      (_) => consent.complete(),
    );
    await consent.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    if (!await ConsentInformation.instance.canRequestAds()) return false;
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
      // OLFA is for adults, but ads stay family-friendly by default (admin can change).
      maxAdContentRating: switch (config.maxAdContentRating) {
        'G' => MaxAdContentRating.g,
        'T' => MaxAdContentRating.t,
        'MA' => MaxAdContentRating.ma,
        _ => MaxAdContentRating.pg,
      },
      tagForChildDirectedTreatment: TagForChildDirectedTreatment.no,
      tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.no,
    ));
    return true;
  }

  String _unitId(DiscoveryAds c) => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => c.iosUnitId,
        TargetPlatform.android => c.androidUnitId,
        _ => '',
      };

  @override
  Future<LoadedNativeAd?> load(DiscoveryAds config) async {
    final unit = _unitId(config);
    if (unit.isEmpty || !await prepare(config)) return null;
    final done = Completer<LoadedNativeAd?>();
    final ad = NativeAd(
      adUnitId: unit,
      request: AdRequest(nonPersonalizedAds: !config.personalized),
      nativeAdOptions: NativeAdOptions(adChoicesPlacement: AdChoicesPlacement.topRightCorner, mediaAspectRatio: MediaAspectRatio.portrait),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: OlfaColors.white,
        cornerRadius: 18,
        callToActionTextStyle: NativeTemplateTextStyle(textColor: OlfaColors.white, backgroundColor: OlfaColors.primary, style: NativeTemplateFontStyle.bold, size: 16),
        primaryTextStyle: NativeTemplateTextStyle(textColor: OlfaColors.black, style: NativeTemplateFontStyle.bold, size: 17),
        secondaryTextStyle: NativeTemplateTextStyle(textColor: OlfaColors.black, style: NativeTemplateFontStyle.normal, size: 14),
        tertiaryTextStyle: NativeTemplateTextStyle(textColor: OlfaColors.black, style: NativeTemplateFontStyle.normal, size: 13),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!done.isCompleted) done.complete(_AdMobAd(ad as NativeAd));
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('ads: no ad (${error.code})');
          if (!done.isCompleted) done.complete(null);
        },
      ),
    );
    unawaited(ad.load());
    return done.future.timeout(const Duration(seconds: 30), onTimeout: () {
      ad.dispose();
      return null;
    });
  }
}

class _AdMobAd implements LoadedNativeAd {
  _AdMobAd(this._ad);
  final NativeAd _ad;
  @override
  final DateTime loadedAt = DateTime.now();
  bool _disposed = false;

  @override
  Widget view() => AdWidget(ad: _ad);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ad.dispose();
  }
}
