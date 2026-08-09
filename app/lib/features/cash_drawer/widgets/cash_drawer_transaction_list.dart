import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/cash_drawer_service.dart';
import '../../../data/models/cash_drawer_transaction.dart';
import '../../../providers/cash_drawer_provider.dart';
import '../../../shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'cash_drawer_edit_dialog.dart';

/// Cash-drawer transaction list with infinite-scroll pagination (DG-343
/// Phase 3, FR3/FR4/FR5, AC1–AC5).
///
/// Renders the unified cash-transaction list for a single drawer (active or
/// closed) using [cashDrawerTransactionsProvider]. Each row is a [Card]
/// showing the transaction type label (AC3), signed amount with `+`/`-`
/// prefix and green/red colour (AC5), timestamp (AC1), and note (AC1).
///
/// Infinite-scroll (FR4/AC2): a [ScrollController] monitors scroll position
/// and requests the next page (growing `offset`) when the user nears the
/// bottom. Loaded pages are accumulated in [_loadedItems] so the list grows
/// lazily — the [ListView.builder] only renders visible rows (NFR2).
///
/// Polling (FR3/AC4): when [poll] is `true` (active drawer tab), a 30s
/// [Timer.periodic] invalidates [cashDrawerTransactionsProvider] for the
/// active drawer's first page and resets the accumulated list so the
/// newest-first view refreshes within 30 seconds of a new transaction —
/// mirroring the existing [cashDrawerStatusProvider] polling pattern in
/// `_CashDrawerScreenState`. Closed-drawer views do not poll.
///
/// DG-379 Phase 4.3 (FR1-FR3, AC1/AC2/AC4/AC5/AC7): when [reconciled] is
/// `false`, tapping an open (`cash_drawer_open`) or close
/// (`cash_drawer_close_adjust`) transaction card opens the edit dialog. On
/// save the service PATCHes the entry and the list refreshes immediately
/// (AC7). When [reconciled] is `true` (AC5), the edit affordance is hidden —
/// tapping a card shows a lock-notice snackbar instead of the dialog.
class CashDrawerTransactionList extends ConsumerStatefulWidget {
  const CashDrawerTransactionList({
    super.key,
    required this.drawerId,
    this.poll = false,
    this.pageSize = 50,
    this.reconciled = false,
  });

  /// The drawer whose transactions are displayed. The active drawer (when
  /// [poll] is `true`) or a closed drawer (when `false`).
  final int drawerId;

  /// Whether to poll the first page on a 30s interval (FR3/AC4). Set to
  /// `true` for the active-drawer tab and `false` for the closed-drawer
  /// detail view.
  final bool poll;

  /// Page size used for each [cashDrawerTransactionsProvider] request.
  /// Defaults to 50 to match the backend default and the history list.
  final int pageSize;

  /// DG-379 Phase 4.3 (FR7, AC5): whether the drawer is reconciled. When
  /// `true`, transaction cards are not tappable for editing — a lock-notice
  /// snackbar is shown instead. Defaults to `false` (editable).
  final bool reconciled;

  @override
  ConsumerState<CashDrawerTransactionList> createState() =>
      _CashDrawerTransactionListState();
}

class _CashDrawerTransactionListState
    extends ConsumerState<CashDrawerTransactionList> {
  final ScrollController _scrollController = ScrollController();

  /// Accumulated transactions across all loaded pages, newest-first.
  final List<CashDrawerTransaction> _loadedItems = [];

  /// Total transaction count reported by the backend (across all pages).
  int _total = 0;

  /// Next offset to request for infinite-scroll. Equals the count of items
  /// loaded so far.
  int _nextOffset = 0;

  /// Whether a page request is currently in-flight. Guards against stacking
  /// duplicate `loadMore` calls when the user scrolls rapidly.
  bool _isLoadingPage = false;

  /// Whether the most recent page request failed. Surfaces a retry row at
  /// the bottom of the list.
  bool _pageFailed = false;

  /// 30s polling timer for the active drawer (FR3/AC4). Null when
  /// [CashDrawerTransactionList.poll] is `false`.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.poll) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) {
          if (!mounted) return;
          _resetAndRefresh();
        },
      );
    }
    // Fetch the first page after the first build so the provider is wired.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirstPage());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Reloads the first page and clears accumulated state. Used by the 30s
  /// poll (FR3/AC4) so the active drawer reflects new transactions.
  void _resetAndRefresh() {
    if (!mounted) return;
    setState(() {
      _loadedItems.clear();
      _nextOffset = 0;
      _total = 0;
      _pageFailed = false;
    });
    // Invalidate the cached first page so the next read re-fetches fresh
    // data rather than returning the cached page.
    ref.invalidate(cashDrawerTransactionsProvider(
      CashDrawerTransactionsFilter(
        drawerId: widget.drawerId,
        limit: widget.pageSize,
        offset: 0,
      ),
    ));
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    setState(() {
      _isLoadingPage = true;
      _pageFailed = false;
    });
    try {
      final resp = await ref.read(cashDrawerTransactionsProvider(
        CashDrawerTransactionsFilter(
          drawerId: widget.drawerId,
          limit: widget.pageSize,
          offset: 0,
        ),
      ).future);
      if (!mounted) return;
      setState(() {
        _loadedItems
          ..clear()
          ..addAll(resp.items);
        _total = resp.total;
        _nextOffset = resp.items.length;
        _isLoadingPage = false;
        _pageFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPage = false;
        _pageFailed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingPage || _pageFailed) return;
    // Stop when we've loaded every page the backend says exists.
    if (_total > 0 && _nextOffset >= _total) return;
    // Defensive: if the first page hasn't resolved yet, don't stack a
    // second request on top of it.
    if (_nextOffset == 0) return;

    setState(() => _isLoadingPage = true);
    try {
      final resp = await ref.read(cashDrawerTransactionsProvider(
        CashDrawerTransactionsFilter(
          drawerId: widget.drawerId,
          limit: widget.pageSize,
          offset: _nextOffset,
        ),
      ).future);
      if (!mounted) return;
      setState(() {
        // Deduplicate by id in case the backend shifts the page boundary
        // (e.g. a new transaction inserts at the top between page loads).
        for (final item in resp.items) {
          if (!_loadedItems.contains(item)) {
            _loadedItems.add(item);
          }
        }
        _total = resp.total;
        _nextOffset += resp.items.length;
        _isLoadingPage = false;
        _pageFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPage = false;
        _pageFailed = true;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Trigger `loadMore` when within 2 viewport heights of the bottom so
    // the next page is ready before the user reaches the end.
    if (position.pixels >= position.maxScrollExtent - position.viewportDimension * 2) {
      _loadMore();
    }
  }

  /// DG-379 Phase 4.3 + DG-381 Phase 1 tap handler.
  ///
  /// DG-381 Phase 1 (FR1/FR2/FR4/FR5, AC1/AC2/AC4/AC5): for `payment_transaction`
  /// rows with a non-empty [CashDrawerTransaction.reference], navigates to
  /// `/orders/:id` via `context.push()`. Back returns to the originating cash
  /// drawer screen (go_router stacks the pushed route on top of the current
  /// route). Rows with an empty `reference` are not tappable (FR4). The
  /// reconciled state does not affect navigation — `payment_transaction` rows
  /// are read-only order references, not editable drawer entries.
  ///
  /// DG-379 Phase 4.3 (FR1-FR3, AC1/AC2/AC5/AC7): for open/close transaction
  /// cards, when the drawer is reconciled (AC5), shows a lock-notice snackbar
  /// and returns. Otherwise opens the edit dialog; on save, PATCHes the entry
  /// via [CashDrawerService.editTransaction] and refreshes the list (AC7).
  /// Non-editable, non-navigable types (cash-in, cash-out, expense) are
  /// ignored — only `cash_drawer_open` and `cash_drawer_close_adjust` are
  /// editable per the backend; only `payment_transaction` is navigable.
  Future<void> _handleTransactionTap(
    BuildContext context,
    CashDrawerTransaction transaction,
  ) async {
    // DG-381 FR2/FR4: payment_transaction rows navigate to order detail when
    // an order ref is present. Checked first so sale rows never fall through
    // to the edit path (which would no-op them anyway).
    if (transaction.type == 'payment_transaction') {
      if (transaction.reference.isEmpty) return; // FR4: no ref → not tappable
      context.push('/orders/${transaction.reference}');
      return;
    }
    // Only open/close transactions are editable (DG-379 FR1/FR2).
    final editable = transaction.type == 'cash_drawer_open' ||
        transaction.type == 'cash_drawer_close_adjust';
    if (!editable) return;
    // AC5: reconciled drawers lock editing.
    if (widget.reconciled) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(VN.cashDrawerEditLockedReconciled)),
      );
      return;
    }
    final entryId = int.tryParse(transaction.id);
    if (entryId == null) return;
    // amount is signed; the edit dialog edits the absolute magnitude.
    final currentAmount = transaction.amount.abs();
    final result = await showEditTransactionDialog(
      context,
      currentAmount: currentAmount,
      currentNotes: transaction.note,
      txnTypeLabel: VN.cashDrawerTxnTypeLabel(transaction.type),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(cashDrawerServiceProvider).editTransaction(
            widget.drawerId,
            entryId,
            amount: result.amount,
            notes: result.notes,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(VN.cashDrawerEditTxnSaved)),
      );
      // AC7: auto-refresh the transaction list after a successful edit.
      _resetAndRefresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${VN.apiError}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedItems.isEmpty && _isLoadingPage) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadedItems.isEmpty && _pageFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(VN.apiError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _resetAndRefresh,
              child: const Text(VN.retry),
            ),
          ],
        ),
      );
    }
    if (_loadedItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            VN.cashDrawerTransactionsTab,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _loadedItems.length + _tailItemCount,
      itemBuilder: (context, index) {
        if (index < _loadedItems.length) {
          return _TransactionCard(
            transaction: _loadedItems[index],
            reconciled: widget.reconciled,
            onTap: _handleTransactionTap,
          );
        }
        // Tail row: loading indicator, retry row, or end-of-list marker for
        // the next page.
        if (_pageFailed) {
          return _RetryRow(onRetry: _loadMore);
        }
        if (_isLoadingPage) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        // All pages loaded — render a small "end of list" marker so the
        // user knows there's nothing more to load.
        if (_total > 0 && _nextOffset >= _total) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                VN.cashDrawerHistory,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          );
        }
        // Defensive: tail out of range (shouldn't happen).
        return const SizedBox.shrink();
      },
    );
  }

  /// Number of trailing rows appended after the loaded items: 1 when a page
  /// is loading, failed, or when there are more pages to load (end marker).
  int get _tailItemCount {
    if (_pageFailed || _isLoadingPage) return 1;
    if (_total > 0 && _nextOffset >= _total && _loadedItems.isNotEmpty) return 1;
    return 0;
  }
}

/// A single transaction row (AC1/AC3/AC5).
///
/// Card layout:
///   title  — type label (short VN, e.g. "Mở quầy", "Bán hàng")
///   amount — signed VND with `+`/`-` prefix, green for inflow / red for outflow
///   subtitle — timestamp (dd/MM/yyyy HH:mm) and note when present
///
/// DG-379 Phase 4.3 (FR1-FR3, AC1/AC2/AC5): when [onTap] is non-null and the
/// transaction type is editable (open/close), the card is tappable. A small
/// edit icon is shown on editable rows so the owner discovers the affordance.
/// When [reconciled] is `true` (AC5) the edit icon is hidden (the [onTap]
/// still fires to show the lock-notice snackbar via the parent handler).
///
/// DG-381 Phase 1 (FR1/FR2/FR4, AC1/AC2/AC4): `payment_transaction` rows with
/// a non-empty [CashDrawerTransaction.reference] are tappable for navigation
/// to `OrderDetailScreen`. A small chevron icon is shown on navigable rows so
/// the user discovers the affordance. Rows with an empty `reference` are not
/// tappable (FR4).
class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.transaction,
    this.reconciled = false,
    this.onTap,
  });

  final CashDrawerTransaction transaction;

  /// Whether the owning drawer is reconciled (hides the edit icon, AC5).
  final bool reconciled;

  /// Invoked when the card is tapped. The parent decides whether to open the
  /// edit dialog, show the reconciled lock notice, or navigate to order
  /// detail.
  final Future<void> Function(BuildContext context, CashDrawerTransaction txn)?
      onTap;

  /// Whether this transaction type is editable (open/close only, FR1/FR2).
  bool get _isEditableType =>
      transaction.type == 'cash_drawer_open' ||
      transaction.type == 'cash_drawer_close_adjust';

  /// DG-381 FR1/FR4: whether this row is navigable to order detail. Only
  /// `payment_transaction` rows with a non-empty `reference` are navigable.
  bool get _isNavigableType =>
      transaction.type == 'payment_transaction' &&
      transaction.reference.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inflow = transaction.isInflow;
    final signedAmount = inflow
        ? '+${formatVND(transaction.amount.toDouble())}'
        : '-${formatVND(transaction.amount.abs().toDouble())}';
    final amountColor = inflow ? Colors.green.shade700 : theme.colorScheme.error;
    // Wrap the card content so the whole row is tappable when an edit
    // affordance is available (open/close type + a non-null tap handler).
    final canEdit = _isEditableType && onTap != null;
    // DG-381 FR1: navigable sale rows are tappable for navigation.
    final canNavigate = _isNavigableType && onTap != null;
    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: (canEdit || canNavigate)
            ? () => onTap!(context, transaction)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            VN.cashDrawerTxnTypeLabel(transaction.type),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        // AC5: hide the edit icon when the drawer is
                        // reconciled. The tap still fires so the parent can
                        // surface the lock-notice snackbar.
                        if (canEdit && !reconciled) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                        // DG-381 FR1: show a chevron on navigable sale rows
                        // so the user discovers the navigation affordance.
                        if (canNavigate) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDisplay(transaction.timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                    ),
                    if (transaction.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        transaction.note,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    // DG-343 Phase 4: reference information (order ref + customer
                    // name for payment transactions; summary + staff/provider for
                    // expenses) shown below the note in smaller, lighter text.
                    if (transaction.reference.isNotEmpty ||
                        transaction.referenceDetail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (transaction.reference.isNotEmpty)
                            transaction.reference,
                          if (transaction.referenceDetail.isNotEmpty)
                            transaction.referenceDetail,
                        ].join(' — '),
                        style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                signedAmount,
                style: theme.textTheme.titleMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    return card;
  }
}

/// Retry row shown at the tail when a `loadMore` request fails.
class _RetryRow extends StatelessWidget {
  const _RetryRow({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(VN.apiError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text(VN.retry),
            ),
          ],
        ),
      ),
    );
  }
}