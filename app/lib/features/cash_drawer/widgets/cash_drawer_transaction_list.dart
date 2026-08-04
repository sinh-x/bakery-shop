import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cash_drawer_transaction.dart';
import '../../../providers/cash_drawer_provider.dart';
import '../../../shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

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
class CashDrawerTransactionList extends ConsumerStatefulWidget {
  const CashDrawerTransactionList({
    super.key,
    required this.drawerId,
    this.poll = false,
    this.pageSize = 50,
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
          return _TransactionCard(transaction: _loadedItems[index]);
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
class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.transaction});

  final CashDrawerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inflow = transaction.isInflow;
    final signedAmount = inflow
        ? '+${formatVND(transaction.amount.toDouble())}'
        : '-${formatVND(transaction.amount.abs().toDouble())}';
    final amountColor = inflow ? Colors.green.shade700 : theme.colorScheme.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    VN.cashDrawerTxnTypeLabel(transaction.type),
                    style: theme.textTheme.titleSmall,
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
    );
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