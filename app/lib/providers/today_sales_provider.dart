import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'today_journal_provider.dart';

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
/// Reuses the shared [todayJournalProvider] (DG-374 cycle-3 C3-2) so today's
/// journal entries are fetched once and shared with
/// [dashboardRevenueStockProvider]. This provider only folds the shared entry
/// list into the cash (1101) and bank (1200 family) debit totals — no
/// duplicate journal API call.
///
/// Pagination (CQ-1): handled by [todayJournalProvider], which pages through
/// the journal in [journalFetchPageSize] batches so totals stay complete on
/// high-volume days (>500 entries).
final FutureProvider<TodayPaymentSplit> todayPaymentSplitProvider =
    FutureProvider<TodayPaymentSplit>((ref) async {
  final entries = await ref.watch(todayJournalProvider.future);

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
