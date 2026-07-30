import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/order_service.dart';
import '../../../data/api/staff_service.dart';
import '../../../data/models/order.dart';
import '../../../features/auth/auth_provider.dart';
import '../../../providers/order/order_list_providers.dart';
import '../../../providers/staff_provider.dart';
import '../../../providers/user_binding_provider.dart';

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

  bool get canClaim => isAdmin || role == 'giao-hang';
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
/// refreshes the shared [orderListProvider] so all delivery cards update
/// (FR5/FR6/AC6/AC8). One instance per `orderRef`.
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
      return updated;
    });
  }

  Future<void> unclaim() async {
    final service = ref.read(orderServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final updated = await service.unassignOrder(_orderRef);
      ref.read(orderListProvider.notifier).refresh();
      return updated;
    });
  }
}

final orderClaimProvider =
    AsyncNotifierProvider<OrderClaimNotifier, Order?>(
  OrderClaimNotifier.new,
);