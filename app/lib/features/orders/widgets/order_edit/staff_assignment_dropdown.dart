import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/staff_service.dart';
import '../../../../providers/order/delivery_staff_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Staff assignment `DropdownButtonFormField` for the order edit wizard
/// delivery stage (DG-304 Phase 5 / FR8/AC5/AC6). Populated from active
/// delivery-role staff (role "giao-hang") via [deliveryStaffForAssignmentProvider];
/// deactivated staff are excluded (FR10). An "unassign" option (null) is the
/// first item so an admin can clear the assignment (FR6).
///
/// Follows the `DropdownButtonFormField` pattern from
/// `staff_binding_section.dart`.
class StaffAssignmentDropdown extends ConsumerWidget {
  const StaffAssignmentDropdown({
    super.key,
    required this.assignedStaffId,
    required this.onChanged,
  });

  /// Currently selected staff id, or null when unassigned.
  final String? assignedStaffId;

  /// Called with the new staff id, or null when the user clears the
  /// assignment via the "Chưa gán" option. When null, the dropdown is
  /// disabled (used by the detail screen while a save is in flight).
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(deliveryStaffForAssignmentProvider);
    return staffAsync.when(
      data: (staffList) => _buildDropdown(context, staffList),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          OrdersLabels.assignStaffLoadError,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildDropdown(BuildContext context, List<StaffMember> staffList) {
    // If the order is already assigned to a staff member no longer in the
    // active delivery list (e.g. deactivated — FR10 keeps existing
    // assignments), synthesize an item so the current value still renders
    // rather than appearing blank.
    final staffIds = staffList.map((s) => s.id.toString()).toSet();
    final hasAssignedItem =
        assignedStaffId == null || staffIds.contains(assignedStaffId);
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text(OrdersLabels.assignStaffUnassign),
      ),
      ...staffList.map(
        (s) => DropdownMenuItem<String?>(
          value: s.id.toString(),
          child: Text(s.name),
        ),
      ),
      if (!hasAssignedItem)
        DropdownMenuItem<String?>(
          value: assignedStaffId,
          child: Text(OrdersLabels.assignStaffInactive(assignedStaffId!)),
        ),
    ];
    return DropdownButtonFormField<String?>(
      value: assignedStaffId,
      decoration: const InputDecoration(
        labelText: OrdersLabels.assignStaffLabel,
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person_outline),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}