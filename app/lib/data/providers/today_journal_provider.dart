import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/accounting_service.dart';
import '../models/journal_entry.dart';
import '../../shared/constants/journal.dart';
import '../../shared/utils/date_formatting.dart';

/// Fetches all of today's journal entries once and shares them across the
/// dashboard and Today Sales providers (DG-374 cycle-3 C3-2).
///
/// Both `dashboardRevenueStockProvider` (revenue account 4100 credits) and
/// the former `todayPaymentSplitProvider` (cash 1101 / bank 1200-family
/// debits) used to each issue their own paginated journal fetch for the same
/// day, so a single pull-to-refresh triggered two redundant API calls for the
/// same `todayStr`. This provider performs the fetch a single time; the
/// consumers watch it and fold the shared entry list into their respective
/// totals, eliminating the duplicate fetch.
///
/// Pagination (CQ-1): delegates to [fetchAllJournalEntries] so high-volume
/// days (>500 entries) page through the journal in [journalFetchPageSize]
/// batches until the API reports no more entries.
///
/// Date bounds (DG-378 Phase 2 / FR6 / NFR3): the `since`/`until` parameters
/// use full timestamp bounds (`T00:00:00` to next-day `T00:00:00`) matching
/// the backend `_day_bounds` pattern. The previous bare-date
/// (`YYYY-MM-DD`) comparison caused an all-zero-cards bug because SQLite
/// string-compares `transaction_date` (a full ISO timestamp like
/// `2026-08-09T10:30:00`) against the `until` value, and
/// `'2026-08-09T10:30:00' <= '2026-08-09'` is false (the `T` suffix sorts
/// after the bare date), excluding every entry of the day.
final FutureProvider<List<JournalEntry>> todayJournalProvider =
    FutureProvider<List<JournalEntry>>((ref) async {
  final accounting = ref.watch(accountingServiceProvider);
  final now = DateTime.now();
  final since = '${formatApiDate(now)}T00:00:00';
  final nextDay = now.add(const Duration(days: 1));
  final until = '${formatApiDate(nextDay)}T00:00:00';
  return fetchAllJournalEntries(accounting, since, until: until);
});
