/// One cell of the order-breakdown matrix returned by
/// `GET /api/reports/order-breakdown` (DG-391 Phase 2).
///
/// A cell aggregates all orders for one combination of order source
/// (`orders.source`) and delivery type (`orders.delivery_type`) whose
/// effective date (`due_date`; POS/reconciliation sources fall back to
/// `created_at`) falls within the queried period. Revenue per cell is the
/// sum of `orders.total_price`, so the breakdown totals reconcile with the
/// period-summary revenue (FR3 alignment).
class OrderBreakdownCell {
  final String source;
  final String deliveryType;
  final int orderCount;
  final double revenue;

  const OrderBreakdownCell({
    required this.source,
    required this.deliveryType,
    required this.orderCount,
    required this.revenue,
  });

  factory OrderBreakdownCell.fromJson(Map<String, dynamic> json) {
    return OrderBreakdownCell(
      source: json['source'] as String? ?? '',
      deliveryType: json['deliveryType'] as String? ?? '',
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Order-breakdown report returned by `GET /api/reports/order-breakdown`
/// (DG-391 Phase 2 / FR1 / AC5).
///
/// The backend responds with a JSON array (not an object) of
/// [OrderBreakdownCell]s grouped by `source` × `deliveryType`. This model
/// wraps that list so it can flow through Riverpod providers alongside the
/// other period report families. Parsing accepts a raw JSON list directly
/// via [OrderBreakdown.fromJsonList], or a single cell via
/// [OrderBreakdownCell.fromJson].
class OrderBreakdown {
  final List<OrderBreakdownCell> cells;

  const OrderBreakdown({required this.cells});

  /// Parses the raw JSON array returned by the endpoint into an
  /// [OrderBreakdown]. Tolerant of a non-list body (treated as empty) so a
  /// malformed response never crashes the dashboard.
  factory OrderBreakdown.fromJsonList(Object? json) {
    if (json is List) {
      return OrderBreakdown(
        cells: json
            .map((c) => OrderBreakdownCell.fromJson(c as Map<String, dynamic>))
            .toList(growable: false),
      );
    }
    return const OrderBreakdown(cells: []);
  }
}