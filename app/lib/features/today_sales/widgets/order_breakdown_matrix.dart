import 'package:flutter/material.dart';

import '../../../data/models/order_breakdown.dart';
import 'order_breakdown_matrix_table.dart';
import 'order_breakdown_mode.dart';

/// The source × delivery_type matrix (FR7 / NFR1).
///
/// Sources are ordered per the fixed business priority
/// (`_sourcePriority`); any source not in the priority list sorts
/// alphabetically after the known ones. Delivery types use their natural
/// occurrence order in the data (alphabetically sorted for determinism).
///
/// The table itself is rendered by [OrderBreakdownMatrixTable] (extracted
/// to its own file — DG-391 cycle-1 review fix CQ-2).
class OrderBreakdownMatrix extends StatelessWidget {
  const OrderBreakdownMatrix({
    super.key,
    required this.cells,
    required this.mode,
  });

  final List<OrderBreakdownCell> cells;
  final OrderBreakdownMode mode;

  /// Fixed business-defined source ordering (FR7). Sources not listed
  /// here are appended alphabetically.
  static const _sourcePriority = <String>[
    'Tại tiệm - POS',
    'Tại tiệm',
    'Facebook-DoanGia',
    'Facebook-Page-mới',
    'Zalo',
    'Điện thoại',
    'app',
  ];

  @override
  Widget build(BuildContext context) {
    final sources = _sortedSources(cells);
    final deliveryTypes = _sortedDeliveryTypes(cells);
    final totalRevenue = cells.fold<double>(0, (s, c) => s + c.revenue);
    final totalCount = cells.fold<int>(0, (s, c) => s + c.orderCount);

    // Lookup cell by (source, deliveryType).
    final byKey = <String, OrderBreakdownCell>{};
    for (final c in cells) {
      byKey['${c.source}\u0000${c.deliveryType}'] = c;
    }
    // Group cells by delivery type for robust column-total lookup
    // (CQ-4 fix — avoids fragile substring matching on composite keys).
    final byDeliveryType = <String, List<OrderBreakdownCell>>{};
    for (final c in cells) {
      byDeliveryType.putIfAbsent(c.deliveryType, () => []).add(c);
    }

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: OrderBreakdownMatrixTable(
            sources: sources,
            deliveryTypes: deliveryTypes,
            byKey: byKey,
            byDeliveryType: byDeliveryType,
            mode: mode,
            totalRevenue: totalRevenue,
            totalCount: totalCount,
          ),
        ),
      ),
    );
  }

  List<String> _sortedSources(List<OrderBreakdownCell> cells) {
    final present = cells.map((c) => c.source).toSet();
    final ordered = <String>[];
    for (final s in _sourcePriority) {
      if (present.contains(s)) ordered.add(s);
    }
    final remaining = present.difference(_sourcePriority.toSet()).toList()
      ..sort();
    ordered.addAll(remaining);
    return ordered;
  }

  List<String> _sortedDeliveryTypes(List<OrderBreakdownCell> cells) {
    final types = cells.map((c) => c.deliveryType).toSet().toList()..sort();
    return types;
  }
}