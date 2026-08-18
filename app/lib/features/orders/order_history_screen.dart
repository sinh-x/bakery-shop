import 'package:bakery_app/shared/utils.dart' show statusMap;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../data/providers/order/order_list_providers.dart';
import '../../shared/theme/bakery_theme.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/order_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
const _historyStatuses = <String>[
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'delivered',
  'completed',
  'cancelled',
];

enum _DateFilterMode { single, range }

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  final _searchController = TextEditingController();
  _DateFilterMode _mode = _DateFilterMode.range;
  String _searchQuery = '';
  String? _rangeError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Order> _applySearch(List<Order> orders) {
    if (_searchQuery.trim().isEmpty) return orders;
    final q = _searchQuery.trim().toLowerCase();
    return orders.where((o) {
      return o.customerName.toLowerCase().contains(q) ||
          o.customerPhone.contains(q) ||
          o.orderRef.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _pickSingleDate(DateTime initialDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _mode = _DateFilterMode.single;
      _rangeError = null;
    });
    await ref.read(orderHistoryPaginationProvider.notifier).setSingleDate(picked);
  }

  Future<void> _pickRange(DateTime initialFrom, DateTime initialTo) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: initialFrom, end: initialTo),
    );
    if (picked == null) return;

    final notifier = ref.read(orderHistoryPaginationProvider.notifier);
    final validation = notifier.validateRange(picked.start, picked.end);
    if (validation != null) {
      setState(() {
        _rangeError = validation;
        _mode = _DateFilterMode.range;
      });
      return;
    }

    setState(() {
      _mode = _DateFilterMode.range;
      _rangeError = null;
    });
    await notifier.setDateRange(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context) {
    // DG-409 Phase 4 (FR12): paginated order history with infinite-scroll +
    // loading indicator. Active orders remain unpaginated (FR9) via the
    // separate orderListProvider.
    final historyAsync = ref.watch(orderHistoryPaginationProvider);
    final notifier = ref.read(orderHistoryPaginationProvider.notifier);
    final fromDate = notifier.fromDate;
    final toDate = notifier.toDate;

    return Scaffold(
      appBar: AppBar(
        title: const Text(OrdersLabels.lichSuDonHang),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: SharedLabels.lamMoi,
            onPressed: notifier.refresh,
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text(OrdersLabels.lichSuDonHangLocMotNgay),
                      selected: _mode == _DateFilterMode.single,
                      onSelected: (_) =>
                          setState(() => _mode = _DateFilterMode.single),
                    ),
                    ChoiceChip(
                      label: const Text(OrdersLabels.lichSuDonHangLocKhoangNgay),
                      selected: _mode == _DateFilterMode.range,
                      onSelected: (_) =>
                          setState(() => _mode = _DateFilterMode.range),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(
                        _mode == _DateFilterMode.single
                            ? formatDisplayDate(fromDate)
                            : '${formatDisplayDate(fromDate)} - ${formatDisplayDate(toDate)}',
                      ),
                      onPressed: () {
                        if (_mode == _DateFilterMode.single) {
                          _pickSingleDate(fromDate);
                        } else {
                          _pickRange(fromDate, toDate);
                        }
                      },
                    ),
                  ],
                ),
                if (_rangeError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _rangeError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: OrdersLabels.lichSuDonHangTimKiem,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: historyAsync.when(
              loading: () => const _OrderHistorySkeleton(),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(SharedLabels.apiError),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: notifier.refresh,
                        child: const Text(SharedLabels.retry),
                      ),
                    ],
                  ),
                ),
              ),
              data: (state) {
                final orders = state.loaded;
                if (orders.isEmpty) {
                  return const Center(child: Text(OrdersLabels.lichSuDonHangTrong));
                }

                final filtered = _applySearch(orders);
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(OrdersLabels.lichSuDonHangKhongTimThay),
                  );
                }

                final grouped = <String, List<Order>>{};
                for (final status in _historyStatuses) {
                  grouped[status] = <Order>[];
                }
                for (final order in filtered) {
                  grouped.putIfAbsent(order.status, () => <Order>[]).add(order);
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollEndNotification &&
                        notification.metrics.pixels >=
                            notification.metrics.maxScrollExtent - 200 &&
                        state.hasMore &&
                        !state.isLoadingMore) {
                      notifier.loadMore();
                    }
                    return false;
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      for (final status in _historyStatuses)
                        if ((grouped[status] ?? const <Order>[]).isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color:
                                        BakeryTheme.statusColors[status] ??
                                        Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  statusMap[status] ?? status,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          ...grouped[status]!.map(
                            (order) => OrderCard(
                              order: order,
                              onTap: () =>
                                  context.push('/orders/${order.orderRef}'),
                            ),
                          ),
                        ],
                      _OrderHistoryLoadMore(
                        state: state,
                        onLoadMore: notifier.loadMore,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer widget shown at the end of the order history list. Renders a
/// loading spinner while fetching the next page, or a "Tải thêm" button when
/// more pages remain (DG-409 Phase 4 / FR12).
class _OrderHistoryLoadMore extends StatelessWidget {
  const _OrderHistoryLoadMore({required this.state, required this.onLoadMore});

  final OrderHistoryPaginationState state;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!state.hasMore && !state.isLoadingMore) {
      return const SizedBox.shrink();
    }
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: Text(
            '${SharedLabels.loadMore} (${state.total - state.loaded.length})',
          ),
        ),
      ),
    );
  }
}

/// Loading skeleton shown while the first history page loads (DG-409
/// Phase 4 / loading indicators).
class _OrderHistorySkeleton extends StatelessWidget {
  const _OrderHistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: List.generate(
        6,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              title: SizedBox(
                height: 16,
                child: LinearProgressIndicator(),
              ),
              subtitle: SizedBox(
                height: 12,
                child: LinearProgressIndicator(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
