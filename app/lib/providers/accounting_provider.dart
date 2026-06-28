import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/accounting_service.dart';
import '../data/models/account.dart';
import '../data/models/account_balance.dart';
import '../data/models/journal_entry.dart';

/// Filter parameters for the journal entries query.
class JournalFilter {
  const JournalFilter({
    this.since,
    this.until,
    this.accountId,
    this.sourceType,
    this.sourceId,
    this.limit = 100,
    this.offset = 0,
  });

  final String? since;
  final String? until;
  final int? accountId;
  final String? sourceType;
  final int? sourceId;
  final int limit;
  final int offset;

  JournalFilter copyWith({
    String? since,
    String? until,
    int? accountId,
    String? sourceType,
    int? sourceId,
    int? limit,
    int? offset,
  }) {
    return JournalFilter(
      since: since ?? this.since,
      until: until ?? this.until,
      accountId: accountId ?? this.accountId,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalFilter &&
          runtimeType == other.runtimeType &&
          since == other.since &&
          until == other.until &&
          accountId == other.accountId &&
          sourceType == other.sourceType &&
          sourceId == other.sourceId &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode =>
      Object.hash(since, until, accountId, sourceType, sourceId, limit, offset);
}

/// Chart of accounts (hierarchical tree).
final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final service = ref.watch(accountingServiceProvider);
  return service.listAccounts();
});

/// Journal entries with filter — FutureProvider.family for parameterized fetch.
final journalEntriesProvider =
    FutureProvider.family<JournalListResponse, JournalFilter>((
  ref,
  filter,
) async {
  final service = ref.watch(accountingServiceProvider);
  return service.listJournal(
    since: filter.since,
    until: filter.until,
    accountId: filter.accountId,
    sourceType: filter.sourceType,
    sourceId: filter.sourceId,
    limit: filter.limit,
    offset: filter.offset,
  );
});

/// Account balances.
final accountBalancesProvider =
    FutureProvider<List<AccountBalance>>((ref) async {
  final service = ref.watch(accountingServiceProvider);
  return service.getBalances();
});