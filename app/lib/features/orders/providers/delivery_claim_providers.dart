import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/order_service.dart';
import '../../../data/api/staff_service.dart';
import '../../../data/models/order.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../providers/order/order_detail_notifier.dart';
import '../../../providers/order/order_list_providers.dart';
import '../../../data/providers/staff_provider.dart';
import '../../../data/providers/user_binding_provider.dart';
import '../../../shared/services/session_cache.dart';

/// Snapshot of the currently logged-in staff member relevant to delivery
/// claiming (DG-310 Phase 4 / FR5/AC9). Combines the staff-user binding
/// (DG-259) with the staff list to resolve the `giao-hang` role client-side,
/// and the auth state for admin detection. Server-side role enforcement
/// remains the source of truth; this only gates button visibility.
class CurrentStaff {
  const CurrentStaff({
    this.staffId,
    this.staffName,
    this.role = '',
    this.isAdmin = false,
  });

  final int? staffId;
  final String? staffName;
  final String role;
  final bool isAdmin;

  bool get canClaim => isAdmin || staffId != null;
  bool get canUnclaim => canClaim;

  String? get staffIdAsString => staffId?.toString();
}

final currentStaffProvider = FutureProvider<CurrentStaff>((ref) async {
  final auth = ref.watch(authProvider);
  final binding = await ref.watch(staffBindingProvider.future);
  if (binding.staffId == null) {
    return CurrentStaff(
      staffName: binding.staffName,
      isAdmin: auth.isAdmin,
    );
  }
  final staffList = await ref.watch(staffListProvider.future);
  final staff = staffList.firstWhere(
    (s) => s.id == binding.staffId,
    orElse: () => StaffMember(
      id: binding.staffId!,
      name: binding.staffName ?? '',
      role: '',
      active: true,
    ),
  );
  return CurrentStaff(
    staffId: binding.staffId,
    staffName: staff.name.isNotEmpty ? staff.name : binding.staffName,
    role: staff.role,
    isAdmin: auth.isAdmin,
  );
});

/// Notifier that performs claim/unclaim on a single delivery order and
/// refreshes both the shared [orderListProvider] (so delivery cards update)
/// and the family-scoped [orderDetailProvider] for the active order (so the
/// order detail screen reflects the new assignment immediately —
/// FR1/FR2/AC1/AC2). One instance per `orderRef`.
class OrderClaimNotifier extends AsyncNotifier<Order?> {
  String _orderRef = '';

  @override
  Future<Order?> build() async => null;

  void setOrderRef(String orderRef) => _orderRef = orderRef;

  Future<void> claim() async {
    final service = ref.read(orderServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final updated = await service.assignOrder(_orderRef);
      ref.read(orderListProvider.notifier).refresh();
      // DG-409 Phase 5 (FR13, AC6): claim mutates the order, invalidate
      // the order-history session cache.
      ref
          .read(sessionCacheProvider)
          .invalidateEntityType(SessionCacheEntity.orderHistory);
      // Refresh the order detail screen so the new assignment shows
      // immediately (FR1/AC1). Matches the established pattern used by
      // payment/work-item notifiers.
      ref.read(orderDetailProvider(_orderRef).notifier).refresh();
      return updated;
    });
  }

  Future<void> unclaim() async {
    final service = ref.read(orderServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final updated = await service.unassignOrder(_orderRef);
      ref.read(orderListProvider.notifier).refresh();
      // DG-409 Phase 5 (FR13, AC6): unclaim mutates the order.
      ref
          .read(sessionCacheProvider)
          .invalidateEntityType(SessionCacheEntity.orderHistory);
      ref.read(orderDetailProvider(_orderRef).notifier).refresh();
      return updated;
    });
  }
}

final orderClaimProvider =
    AsyncNotifierProvider<OrderClaimNotifier, Order?>(
  OrderClaimNotifier.new,
);