import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'order_counts_provider.dart';

/// Count of active orders with completeness "incomplete" (FR1/NFR2).
///
/// Backed by the lightweight `GET /api/orders/counts` endpoint (via
/// [orderCountsProvider]) instead of the full order list so the shell
/// scaffold's bottom-nav badge no longer forces a full order fetch on app
/// start.
///
/// Design decision: returns 0 (empty) on error or during loading rather than
/// showing stale counts. This means badges will be hidden during API outages
/// — degraded UX is intentional to avoid displaying potentially incorrect
/// counts (FR2 degraded UX).
final incompleteCountProvider = Provider<int>((ref) {
  final counts = ref.watch(orderCountsProvider);
  return counts.maybeWhen(data: (d) => d.incomplete, orElse: () => 0);
});