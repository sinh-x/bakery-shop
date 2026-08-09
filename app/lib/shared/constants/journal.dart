/// Shared journal-related constants and helpers used across dashboard and
/// Today Sales providers (DG-374 Phase 5.6-c2-fix / C2-2, C3-1).
///
/// Extracted from the duplicate `journalFetchPageSize` definitions that
/// existed in both `dashboard_metrics_provider.dart` and the former
/// `today_sales_provider.dart` (removed in DG-378 Phase 2) so the providers
/// share a single source of truth for the journal page size.
library;

import '../../data/api/accounting_service.dart';
import '../../data/models/journal_entry.dart';

const int journalFetchPageSize = 500;

/// Fetches all journal entries for the given day, paging through the API in
/// [journalFetchPageSize] batches until the server reports no more entries
/// (DG-374 cycle-3 C3-1 — extracted from the duplicate pagination loops that
/// existed verbatim in `dashboardRevenueStockProvider` and the former
/// `todayPaymentSplitProvider` removed in DG-378 Phase 2).
///
/// [since]/[until] are the inclusive day bounds in API date format
/// (`YYYY-MM-DD`). When [accountId] is non-null the API filters to lines for
/// that account; pass `null` to fetch every entry for the day.
///
/// Returns the concatenated list of [JournalEntry] items across all pages so
/// callers can fold the full set without re-implementing the pagination loop.
Future<List<JournalEntry>> fetchAllJournalEntries(
  AccountingService accounting,
  String since, {
  String? until,
  int? accountId,
}) async {
  final entries = <JournalEntry>[];
  int offset = 0;
  while (true) {
    final resp = await accounting.listJournal(
      since: since,
      until: until ?? since,
      accountId: accountId,
      limit: journalFetchPageSize,
      offset: offset,
    );
    entries.addAll(resp.items);
    if (resp.items.length < journalFetchPageSize) {
      break;
    }
    offset += journalFetchPageSize;
  }
  return entries;
}
