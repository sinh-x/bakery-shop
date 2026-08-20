/// Per-product revenue attribution row returned by
/// `GET /api/reports/product-breakdown` (DG-386 Phase 2).
///
/// One row represents either a single product or the synthetic `Khác`
/// (Others) bucket aggregating all products beyond the top N. Revenue is
/// attributed proportionally to each order item's line value so the sum of
/// all rows reconciles with `period-summary.revenue`.
class ProductBreakdownRow {
  final String name;
  final int quantity;
  final double revenue;
  final double percentage;

  const ProductBreakdownRow({
    required this.name,
    required this.quantity,
    required this.revenue,
    required this.percentage,
  });

  factory ProductBreakdownRow.fromJson(Map<String, dynamic> json) {
    return ProductBreakdownRow(
      name: json['name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Product-breakdown report returned by `GET /api/reports/product-breakdown`
/// (DG-386 Phase 2).
///
/// Contains the top N products by revenue (default 10) plus a single `others`
/// row (`Khác`) aggregating the remaining products, sorted by revenue
/// descending. `totalRevenue` reconciles with the journal 4100 credit total
/// for the period (matches `period-summary.revenue`).
class ProductBreakdown {
  final String period;
  final String startDate;
  final String endDate;
  final String date;
  final double totalRevenue;
  final List<ProductBreakdownRow> products;
  final ProductBreakdownRow others;

  const ProductBreakdown({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.date,
    required this.totalRevenue,
    required this.products,
    required this.others,
  });

  factory ProductBreakdown.fromJson(Map<String, dynamic> json) {
    final productsRaw = json['products'] as List? ?? const [];
    final othersRaw = json['others'] as Map<String, dynamic>?;
    return ProductBreakdown(
      period: json['period'] as String? ?? '',
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      date: json['date'] as String? ?? '',
      totalRevenue: (json['totalRevenue'] as num?)?.toDouble() ?? 0,
      products: productsRaw
          .map((p) => ProductBreakdownRow.fromJson(p as Map<String, dynamic>))
          .toList(growable: false),
      others: othersRaw != null
          ? ProductBreakdownRow.fromJson(othersRaw)
          : const ProductBreakdownRow(
              name: 'Khác', quantity: 0, revenue: 0, percentage: 0),
    );
  }
}