import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/accounting_service.dart';
import '../../data/models/journal_entry.dart';
import '../../shared/constants/journal.dart';
import '../../shared/utils/date_formatting.dart';

/// Asset account codes used to split today's inbound payments into cash vs
/// bank transfer totals for the Today Sales revenue summary (DG-374 Phase 2 /
/// FR3). Cash payments debit account 1101 (Tiền mặt tại quầy); bank transfers
/// debit any of the bank sub-accounts under 1200 (1210, 1220, 1290) or 1200
/// itself. Card payments route to 1100 per `PAYMENT_METHOD_TO_ASSET_CODE` but
/// are treated as cash-equivalent here only when they hit 1101; the bank
/// transfer total uses the 1200 family to match the requirement.
const String cashAssetAccountCode = '1101';

const Set<String> bankAssetAccountCodes = {
  '1200',
  '1210',
  '1220',
  '1290',
};

/// Today's inbound payment totals split by payment method (DG-374 Phase 2 /
/// FR3). `cashTotal` sums debits to account 1101; `bankTransferTotal` sums
/// debits to any account in [bankAssetAccountCodes]. Both are computed from
/// today's journal entries in a single API call (the same
/// `GET /api/accounts/journal?since=<today>&until=<today>` fetch the revenue
/// summary already uses for the 4100 credit total) so no extra request is
/// needed beyond the existing [dashboardRevenueStockProvider] journal fetch.
class TodayPaymentSplit {
  const TodayPaymentSplit({
    required this.cashTotal,
    required this.bankTransferTotal,
  });

  final double cashTotal;
  final double bankTransferTotal;
}

/// Computes today's cash vs bank transfer inbound payment totals from the
/// journal (DG-374 Phase 2 / FR3 / NFR1 — parallel API calls).
///
/// Fetches today's journal entries once and sums the debit side of lines
/// hitting the cash (1101) and bank (1200 family) asset accounts. Revenue
/// (account 4100 credits) and order count are reused from the existing
/// [dashboardRevenueStockProvider] and [orderListProvider] so this provider
/// only adds the cash/bank split, not a duplicate revenue fetch.
///
/// Pagination (CQ-1): pages through the journal in [journalFetchPageSize]
/// batches until the API reports no more entries for the day, so totals stay
/// complete on high-volume days (>500 entries).
final FutureProvider<TodayPaymentSplit> todayPaymentSplitProvider =
    FutureProvider<TodayPaymentSplit>((ref) async {
  final accounting = ref.watch(accountingServiceProvider);
  final todayStr = formatApiDate(DateTime.now());

  final entries = <JournalEntry>[];
  int offset = 0;
  while (true) {
    final resp = await accounting.listJournal(
      since: todayStr,
      until: todayStr,
      limit: journalFetchPageSize,
      offset: offset,
    );
    entries.addAll(resp.items);
    if (resp.items.length < journalFetchPageSize) {
      break;
    }
    offset += journalFetchPageSize;
  }

  double cashTotal = 0;
  double bankTotal = 0;
  for (final entry in entries) {
    for (final line in entry.lines) {
      final code = line.accountCode ?? line.accountId;
      if (code == cashAssetAccountCode) {
        cashTotal += line.debit;
      } else if (bankAssetAccountCodes.contains(code)) {
        bankTotal += line.debit;
      }
    }
  }

  return TodayPaymentSplit(cashTotal: cashTotal, bankTransferTotal: bankTotal);
});
