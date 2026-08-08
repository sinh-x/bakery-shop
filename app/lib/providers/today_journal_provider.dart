import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/accounting_service.dart';
import '../data/models/journal_entry.dart';
import '../shared/constants/journal.dart';
import '../shared/utils/date_formatting.dart';

/// Fetches all of today's journal entries once and shares them across the
/// dashboard and Today Sales providers (DG-374 cycle-3 C3-2).
///
/// Both `dashboardRevenueStockProvider` (revenue account 4100 credits) and
/// `todayPaymentSplitProvider` (cash 1101 / bank 1200-family debits) used to
/// each issue their own paginated journal fetch for the same day, so a single
/// pull-to-refresh triggered two redundant API calls for the same `todayStr`.
/// This provider performs the fetch a single time; the consumers watch it and
/// fold the shared entry list into their respective totals, eliminating the
/// duplicate fetch.
///
/// Pagination (CQ-1): delegates to [fetchAllJournalEntries] so high-volume
/// days (>500 entries) page through the journal in [journalFetchPageSize]
/// batches until the API reports no more entries.
final FutureProvider<List<JournalEntry>> todayJournalProvider =
    FutureProvider<List<JournalEntry>>((ref) async {
  final accounting = ref.watch(accountingServiceProvider);
  final todayStr = formatApiDate(DateTime.now());
  return fetchAllJournalEntries(accounting, todayStr);
});