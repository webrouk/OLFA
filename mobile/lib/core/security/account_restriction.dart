import 'package:flutter/foundation.dart';

/// The admin panel closed this account: permanently ([permanent]) or until [until]
/// (null = until support lifts it). Set from the server's ACCOUNT_BANNED /
/// ACCOUNT_SUSPENDED error; the router then shows the closed-account screen.
@immutable
class AccountRestriction {
  const AccountRestriction({required this.permanent, this.until, this.reason, this.since, this.appealToken});
  final bool permanent;
  final DateTime? until;
  final String? reason;
  final DateTime? since;

  /// Short-lived token that lets a closed account still write to support.
  final String? appealToken;

  static AccountRestriction fromDetails(String code, Map<String, dynamic> d) {
    DateTime? at(String k) => d[k] is String ? DateTime.tryParse(d[k] as String)?.toLocal() : null;
    return AccountRestriction(
      permanent: code == 'ACCOUNT_BANNED' || d['permanent'] == true,
      until: at('until'),
      reason: d['reason'] as String?,
      since: at('since'),
      appealToken: d['appealToken'] as String?,
    );
  }
}

/// Global, so the network layer can raise it and the router can listen to it.
final accountRestriction = ValueNotifier<AccountRestriction?>(null);
