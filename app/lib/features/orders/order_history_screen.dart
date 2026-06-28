import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../providers/order_providers.dart';
import '../../shared/labels/orders.dart';
import '../../shared/theme/bakery_theme.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/order_card.dart';

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
    await ref.read(orderHistoryProvider.notifier).setSingleDate(picked);
  }

  Future<void> _pickRange(DateTime initialFrom, DateTime initialTo) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: initialFrom, end: initialTo),
    );
    if (picked == null) return;

    final notifier = ref.read(orderHistoryProvider.notifier);
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
    final historyAsync = ref.watch(orderHistoryProvider);
    final notifier = ref.read(orderHistoryProvider.notifier);
    final fromDate = notifier.fromDate;
    final toDate = notifier.toDate;

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.lichSuDonHang),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
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
                      label: const Text(VN.lichSuDonHangLocMotNgay),
                      selected: _mode == _DateFilterMode.single,
                      onSelected: (_) =>
                          setState(() => _mode = _DateFilterMode.single),
                    ),
                    ChoiceChip(
                      label: const Text(VN.lichSuDonHangLocKhoangNgay),
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
                    hintText: VN.lichSuDonHangTimKiem,
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(VN.apiError),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: notifier.refresh,
                        child: const Text(VN.retry),
                      ),
                    ],
                  ),
                ),
              ),
              data: (orders) {
                if (orders.isEmpty) {
                  return const Center(child: Text(VN.lichSuDonHangTrong));
                }

                final filtered = _applySearch(orders);
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(VN.lichSuDonHangKhongTimThay),
                  );
                }

                final grouped = <String, List<Order>>{};
                for (final status in _historyStatuses) {
                  grouped[status] = <Order>[];
                }
                for (final order in filtered) {
                  grouped.putIfAbsent(order.status, () => <Order>[]).add(order);
                }

                return ListView(
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
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
