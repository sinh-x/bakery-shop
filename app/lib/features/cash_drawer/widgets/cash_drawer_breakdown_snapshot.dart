/// Snapshot-to-breakdown adapter for closed-drawer history (DG-363 Phase 4 /
/// FR7).
///
/// The backend persists an 8-category breakdown snapshot when a drawer
/// closes (`cash_drawer_breakdown_snapshot` table, v097 migration) and
/// embeds it in the `/status` and `/history` responses (Phase 2). The
/// History tab renders the breakdown directly from this snapshot without
/// re-aggregating live transactions (NFR1: no network request to
/// /transactions; the snapshot is the source of truth for closed drawers).
///
/// This file holds the [breakdownFromSnapshot] adapter plus the canonical
/// category-name map that bridges the backend's string category names to
/// the [CashDrawerBreakdownCategory] enum. Extracted from
/// `cash_drawer_breakdown_card.dart` per NFR3 (file ≤ 300 lines).
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../../data/models/cash_drawer.dart';
import 'cash_drawer_breakdown_card.dart';

/// The canonical category names used by the backend snapshot table
/// (`BREAKDOWN_SNAPSHOT_CATEGORIES` in v097), in fixed order. Matches the
/// `CashDrawerBreakdownCategory` enum names. Used by [breakdownFromSnapshot]
/// to map the persisted string names back to enum values.
const breakdownSnapshotCategoryNames =
    <CashDrawerBreakdownCategory, String>{
  CashDrawerBreakdownCategory.sale: 'sale',
  CashDrawerBreakdownCategory.refund: 'refund',
  CashDrawerBreakdownCategory.expense: 'expense',
  CashDrawerBreakdownCategory.cashIn: 'cashIn',
  CashDrawerBreakdownCategory.cashOut: 'cashOut',
  CashDrawerBreakdownCategory.open: 'open',
  CashDrawerBreakdownCategory.close: 'close',
  CashDrawerBreakdownCategory.busShipping: 'busShipping',
};

/// DG-363 Phase 4 / FR7: build a [CashDrawerBreakdown] directly from a
/// persisted snapshot (list of [CashDrawerBreakdownSnapshotRow]) instead of
/// re-aggregating live transactions. The snapshot is the source of truth
/// for closed drawers (NFR1: no network request to /transactions). Each
/// snapshot row maps to its [CashDrawerBreakdownCategory] by name; missing
/// categories default to a zero row so the breakdown always renders 8 rows
/// (FR1). Group totals (`totalIn`, `totalOut`) are recomputed from the
/// rows so the inflow − outflow reconciliation footer (FR3/AC3) holds.
///
/// Unknown category strings are skipped with a debug print (defensive — the
/// backend only ever stores the 8 canonical names).
CashDrawerBreakdown breakdownFromSnapshot(
    List<CashDrawerBreakdownSnapshotRow> snapshot) {
  final byName = <String, CashDrawerBreakdownSnapshotRow>{
    for (final r in snapshot) r.category: r,
  };
  final rows = <CashDrawerBreakdownRow>[];
  for (final cat in CashDrawerBreakdownCategory.values) {
    final name = breakdownSnapshotCategoryNames[cat]!;
    final row = byName[name];
    if (row == null) {
      rows.add(CashDrawerBreakdownRow(category: cat, totalAmount: 0, count: 0));
      continue;
    }
    rows.add(CashDrawerBreakdownRow(
        category: cat, totalAmount: row.totalAmount, count: row.count));
  }
  int totalIn = 0;
  int totalOut = 0;
  for (final r in rows) {
    if (r.isInflow) {
      if (r.totalAmount > 0) totalIn += r.totalAmount;
    } else {
      if (r.totalAmount < 0) totalOut += r.totalAmount.abs();
    }
  }
  // Defensive: warn if the snapshot contained categories we did not map.
  if (kDebugMode && byName.length > rows.length) {
    debugPrint('breakdownFromSnapshot: unknown categories in snapshot: '
        '${byName.keys.where((k) => !breakdownSnapshotCategoryNames.values.contains(k))}');
  }
  return CashDrawerBreakdown(rows: rows, totalIn: totalIn, totalOut: totalOut);
}