import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/order_service.dart';
import '../../data/models/order.dart';
import '../../shared/labels/shared.dart';
import '../../shared/utils/date_formatting.dart';

class OrderListNotifier extends AsyncNotifier<List<Order>> {
  String? _statusFilter;

  @override
  Future<List<Order>> build() async {
    return _fetch();
  }

  Future<List<Order>> _fetch() async {
    final service = ref.read(orderServiceProvider);
    return service.listOrders(status: _statusFilter, activeOnly: true);
  }

  Future<void> filterByStatus(String? status) async {
    _statusFilter = status;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final orderListProvider = AsyncNotifierProvider<OrderListNotifier, List<Order>>(
  OrderListNotifier.new,
);

class OrderHistoryNotifier extends AsyncNotifier<List<Order>> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  @override
  Future<List<Order>> build() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _toDate = today;
    _fromDate = today.subtract(const Duration(days: 1));
    return _fetch();
  }

  DateTime get fromDate => _fromDate;
  DateTime get toDate => _toDate;

  String? validateRange(DateTime fromDate, DateTime toDate) {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime(toDate.year, toDate.month, toDate.day);
    final dayCount = end.difference(start).inDays + 1;
    if (dayCount < 1) return VN.lichSuDonHangKhoangNgayKhongHopLe;
    if (dayCount > 7) return VN.lichSuDonHangToiDa7Ngay;
    return null;
  }

  Future<void> setDateRange(DateTime fromDate, DateTime toDate) async {
    final error = validateRange(fromDate, toDate);
    if (error != null) {
      throw ArgumentError(error);
    }
    _fromDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    _toDate = DateTime(toDate.year, toDate.month, toDate.day);
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSingleDate(DateTime date) {
    return setDateRange(date, date);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<List<Order>> _fetch() async {
    final service = ref.read(orderServiceProvider);
    return service.listOrders(
      dueDateFrom: _formatDate(_fromDate),
      dueDateTo: _formatDate(_toDate),
      activeOnly: false,
      limit: 200,
    );
  }

  String _formatDate(DateTime date) => formatApiDate(date);
}

final orderHistoryProvider =
    AsyncNotifierProvider<OrderHistoryNotifier, List<Order>>(
      OrderHistoryNotifier.new,
    );

final dashboardOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final service = ref.watch(orderServiceProvider);
  return service.listActiveOrders();
});