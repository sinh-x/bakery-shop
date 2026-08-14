import 'package:flutter/material.dart';

import '../../../data/models/order_breakdown.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import 'order_breakdown_empty_state.dart';
import 'order_breakdown_matrix.dart';
import 'order_breakdown_mode.dart';
import 'order_breakdown_mode_dropdown.dart';

/// Order-breakdown section for the Today Sales screen Tuần/Tháng tabs
/// (DG-391 Phase 3 / FR1, FR2, FR6, FR7 / AC1, AC2).
///
/// Renders a source × delivery_type matrix from the cells returned by
/// `GET /api/reports/order-breakdown` (Phase 2). A dropdown switches
/// between the three display modes ([OrderBreakdownMode]). Rows are
/// sources in a fixed business-defined order (FR7); columns are the
/// distinct delivery types present in the data. A trailing totals row
/// sums order count and revenue.
///
/// The matrix is wrapped in a horizontal [SingleChildScrollView] so it
/// does not overflow on narrow phones (NFR1). All user-facing text uses
/// [SharedLabels] (NFR2 — no inline VN strings).
///
/// The widget is a [StatefulWidget] only to hold the selected dropdown
/// mode; the breakdown data is supplied by the caller (the owning tab
/// body owns the `orderBreakdownProvider` lifecycle). When [breakdown]
/// is `null` or has no cells the empty state is rendered.
///
/// The mode dropdown, matrix table, and empty-state widgets live in
/// their own files (DG-391 cycle-1 review fix CQ-2 — keeps each file
/// within the 200-line widget threshold per
/// `docs/flutter-coding-standards.md` §1/§2).
class OrderBreakdownSection extends StatefulWidget {
  const OrderBreakdownSection({
    super.key,
    required this.breakdown,
  });

  /// Order-breakdown report to render. `null` indicates the caller is
  /// still loading or has no data; the empty state is shown in that case.
  final OrderBreakdown? breakdown;

  @override
  State<OrderBreakdownSection> createState() => _OrderBreakdownSectionState();
}

class _OrderBreakdownSectionState extends State<OrderBreakdownSection> {
  OrderBreakdownMode _mode = OrderBreakdownMode.countRevenue;

  @override
  Widget build(BuildContext context) {
    final cells = widget.breakdown?.cells ?? const <OrderBreakdownCell>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesOrderBreakdownSection),
        const SizedBox(height: 8),
        OrderBreakdownModeDropdown(
          mode: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: 8),
        if (cells.isEmpty)
          const OrderBreakdownEmptyState()
        else
          OrderBreakdownMatrix(cells: cells, mode: _mode),
      ],
    );
  }
}