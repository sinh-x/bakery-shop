import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/order_service.dart';

/// Lightweight urgency/incomplete badge counts for active orders (DG-409
/// Phase 2 / FR1/NFR2/NFR4).
///
/// Fetches `GET /api/orders/counts` instead of deriving from the full order
/// list so the shell scaffold's bottom-nav badges render independently of
/// `orderListProvider` (NFR2 — shell < 500ms p95). The backend degrades to
/// `{"urgency": 0, "incomplete": 0}` on error, but this provider additionally
/// guards transport/parse failures so consumers always see a value.
final orderCountsProvider = FutureProvider<({int urgency, int incomplete})>((
  ref,
) async {
  final service = ref.watch(orderServiceProvider);
  return service.fetchOrderCounts();
});
