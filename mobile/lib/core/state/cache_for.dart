import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps an auto-dispose provider's data for [duration] after its last
/// listener leaves, so going back to a page shows it instantly instead of
/// loading it again. Pull-to-refresh / invalidate still fetch fresh data.
extension CacheFor on AutoDisposeRef<Object?> {
  void cacheFor(Duration duration) {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    onDispose(timer.cancel);
  }
}

/// How long lists and details stay cached between visits.
abstract final class CacheTtl {
  static const list = Duration(minutes: 3);
  static const detail = Duration(minutes: 5);
}
