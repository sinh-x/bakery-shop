import 'package:flutter/material.dart';

import '../../../../data/api/staff_service.dart';
import '../../../../shared/labels/orders.dart';

/// Staff filter dropdown populated from all active staff (FR2/FR4).
/// "All" is always the first option and the default selection (FR4).
/// No extra API call on toggle (NFR1) — uses already-loaded staff.
///
/// Extracted from `delivery_content.dart` (CQ-2, DG-329 Phase 5.6-c1 review
/// remediation) to keep the content file under the 200-line Flutter
/// coding-standards widget threshold (NFR2). This is existing debt
/// catalogued in `docs/code-quality-audit.md`. This is an
/// implementation-detail widget of the delivery tab and is not intended
/// for reuse outside it.
class StaffFilterDropdown extends StatelessWidget {
  const StaffFilterDropdown({
    super.key,
    required this.deliveryStaff,
    required this.selectedStaffId,
    required this.onChanged,
  });

  final List<StaffMember> deliveryStaff;
  final String? selectedStaffId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Ensure the current selection is still in the list (e.g. after a
    // refresh); otherwise fall back to "All".
    final value = (selectedStaffId == null ||
            deliveryStaff.any((s) => s.id.toString() == selectedStaffId))
        ? selectedStaffId
        : null;

    return DropdownButton<String?>(
      value: value,
      hint: const Text(OrdersLabels.staffFilterLabel),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text(OrdersLabels.staffFilterAll),
        ),
        ...deliveryStaff.map(
          (s) => DropdownMenuItem<String?>(
            value: s.id.toString(),
            child: Text(s.name),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}