import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_errors.dart';
import '../../../shared/services/demo_backend.dart';

/// Approximate place of the device. Coordinates are rounded to 2 decimals
/// (≈1 km) on the device and again on the server; they are never shown to
/// anyone — other people only see a rounded distance.
class DetectedLocation {
  const DetectedLocation({required this.latitude, required this.longitude, this.countryIso, this.city});
  final double latitude;
  final double longitude;
  final String? countryIso;
  final String? city;
}

enum LocationOutcome { granted, denied, deniedForever, serviceOff }

double roundCoord(double v) => (v * 100).roundToDouble() / 100;

abstract interface class LocationService {
  /// Asks for permission (when-in-use) and reads a low-accuracy fix.
  Future<(LocationOutcome, DetectedLocation?)> detect();

  /// Sends the rounded location to the server (PUT /me/location).
  Future<void> save(DetectedLocation loc);
}

class DeviceLocationService implements LocationService {
  DeviceLocationService(this._api);
  final ApiClient _api;

  @override
  Future<(LocationOutcome, DetectedLocation?)> detect() async {
    if (!await Geolocator.isLocationServiceEnabled()) return (LocationOutcome.serviceOff, null);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return (LocationOutcome.denied, null);
    if (perm == LocationPermission.deniedForever) return (LocationOutcome.deniedForever, null);
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 12)),
    );
    String? iso, city;
    try {
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        iso = marks.first.isoCountryCode?.toUpperCase();
        city = marks.first.locality ?? marks.first.administrativeArea;
      }
    } catch (_) {
      // Reverse geocoding is optional: the server still sorts by distance.
    }
    return (LocationOutcome.granted, DetectedLocation(latitude: roundCoord(pos.latitude), longitude: roundCoord(pos.longitude), countryIso: iso, city: city));
  }

  @override
  Future<void> save(DetectedLocation loc) => guard(() => _api.dio.put<void>('/me/location', data: {
        'latitude': roundCoord(loc.latitude),
        'longitude': roundCoord(loc.longitude),
        if (loc.countryIso != null) 'countryCode': loc.countryIso,
      }));
}

/// Demo mode: a fixed, clearly-labelled sample place (Dubai). Never used in release builds.
class DemoLocationService implements LocationService {
  DemoLocationService(this._b);
  final DemoBackend _b;
  @override
  Future<(LocationOutcome, DetectedLocation?)> detect() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return (LocationOutcome.granted, DetectedLocation(latitude: 25.2, longitude: 55.27, countryIso: 'AE', city: _b.lang == 'ar' ? 'دبي' : 'Dubai'));
  }

  @override
  Future<void> save(DetectedLocation loc) async => _b.locationCountry = loc.countryIso;
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => useApi ? DeviceLocationService(ref.watch(apiClientProvider)) : DemoLocationService(ref.watch(demoBackendProvider)),
);

/// The last location detected in this session (drives the profile prefill).
class DetectedLocationController extends Notifier<DetectedLocation?> {
  @override
  DetectedLocation? build() => null;
  void set(DetectedLocation? loc) => state = loc;
}

final detectedLocationProvider = NotifierProvider<DetectedLocationController, DetectedLocation?>(DetectedLocationController.new);
