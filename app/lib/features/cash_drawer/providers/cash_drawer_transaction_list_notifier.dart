import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cash_drawer_transaction.dart';

/// Cash-drawer transaction-list state (DG-404 Phase 4.7 / FR2).
///
/// Owns the accumulated `_loadedItems` list, `_total`, `_nextOffset`,
/// `_isLoadingPage`, and `_pageFailed` fields previously mutated via
/// `setState` inside `_CashDrawerTransactionListState`. Keyed by the drawer
/// id via a family provider so each list instance maintains its own
/// accumulation state. Following the codebase convention for
/// `NotifierProvider.family` (arg as constructor param, see
/// `ExpenseHistoryPhotoNotifier`).
class CashDrawerTransactionListState {
  const CashDrawerTransactionListState({
    this.loadedItems = const <CashDrawerTransaction>[],
    this.total = 0,
    this.nextOffset = 0,
    this.isLoadingPage = false,
    this.pageFailed = false,
  });

  final List<CashDrawerTransaction> loadedItems;
  final int total;
  final int nextOffset;
  final bool isLoadingPage;
  final bool pageFailed;

  CashDrawerTransactionListState copyWith({
    List<CashDrawerTransaction>? loadedItems,
    int? total,
    int? nextOffset,
    bool? isLoadingPage,
    bool? pageFailed,
  }) =>
      CashDrawerTransactionListState(
        loadedItems: loadedItems ?? this.loadedItems,
        total: total ?? this.total,
        nextOffset: nextOffset ?? this.nextOffset,
        isLoadingPage: isLoadingPage ?? this.isLoadingPage,
        pageFailed: pageFailed ?? this.pageFailed,
      );
}

class CashDrawerTransactionListNotifier
    extends Notifier<CashDrawerTransactionListState> {
  final int drawerId;

  CashDrawerTransactionListNotifier(this.drawerId);

  @override
  CashDrawerTransactionListState build() =>
      const CashDrawerTransactionListState();

  /// Clear accumulated state before re-fetching the first page (used by the
  /// 30s poll and the post-edit refresh).
  void resetForRefresh() => state = const CashDrawerTransactionListState();

  /// Mark a page request as in-flight (first page).
  void startFirstPage() => state = state.copyWith(
        isLoadingPage: true,
        pageFailed: false,
      );

  /// Set the loaded first page result.
  void setFirstPage(List<CashDrawerTransaction> items, int total) =>
      state = CashDrawerTransactionListState(
        loadedItems: items,
        total: total,
        nextOffset: items.length,
        isLoadingPage: false,
        pageFailed: false,
      );

  /// Mark the first-page request as failed.
  void failFirstPage() => state = state.copyWith(
        isLoadingPage: false,
        pageFailed: true,
      );

  /// Mark a `loadMore` request as in-flight.
  void startLoadMore() => state = state.copyWith(isLoadingPage: true);

  /// Merge a `loadMore` page result into the accumulated list, de-duplicating
  /// by `CashDrawerTransaction` equality (id-based) in case the backend shifts
  /// the page boundary between requests.
  void appendPage(List<CashDrawerTransaction> items, int total) {
    final merged = List<CashDrawerTransaction>.from(state.loadedItems);
    for (final item in items) {
      if (!merged.contains(item)) merged.add(item);
    }
    state = state.copyWith(
      loadedItems: merged,
      total: total,
      nextOffset: state.nextOffset + items.length,
      isLoadingPage: false,
      pageFailed: false,
    );
  }

  /// Mark the `loadMore` request as failed.
  void failLoadMore() => state = state.copyWith(
        isLoadingPage: false,
        pageFailed: true,
      );
}

/// Family provider for the cash-drawer transaction-list state, keyed by
/// drawer id.
final cashDrawerTransactionListProvider =
    NotifierProvider.family<CashDrawerTransactionListNotifier,
        CashDrawerTransactionListState, int>(
            CashDrawerTransactionListNotifier.new);