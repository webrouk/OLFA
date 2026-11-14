import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/services/demo_backend.dart';

abstract interface class SupportRepository {
  Future<List<FaqEntry>> faq();

  /// Returns the ticket number.
  Future<String> submitTicket(String category, String message);
}

class DemoSupportRepository implements SupportRepository {
  DemoSupportRepository(this._b);
  final DemoBackend _b;
  @override
  Future<List<FaqEntry>> faq() => _b.faq();
  @override
  Future<String> submitTicket(String category, String message) => _b.submitTicket(category, message);
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) => DemoSupportRepository(ref.watch(demoBackendProvider)));

final faqProvider = FutureProvider<List<FaqEntry>>((ref) => ref.watch(supportRepositoryProvider).faq());
