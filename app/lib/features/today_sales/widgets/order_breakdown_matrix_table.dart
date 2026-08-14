import 'package:flutter/material.dart';

import '../../../data/models/order_breakdown.dart';
import '../../../shared/labels/shared.dart';
import 'order_breakdown_mode.dart';

/// Renders the order-breakdown matrix as a [Table] with a leading source
/// column, one column per delivery type, and a trailing totals row.
///
/// Extracted from `order_breakdown_matrix.dart` (DG-391 cycle-1 review
/// fix CQ-2) so each widget file stays within the 200-line threshold per
/// `docs/flutter-coding-standards.md` §1.
class OrderBreakdownMatrixTable extends StatelessWidget {
  const OrderBreakdownMatrixTable({
    super.key,
    required this.sources,
    required this.deliveryTypes,
    required this.byKey,
    required this.byDeliveryType,
    required this.mode,
    required this.totalRevenue,
    required this.totalCount,
  });

  final List<String> sources;
  final List<String> deliveryTypes;
  final Map<String, OrderBreakdownCell> byKey;
  final Map<String, List<OrderBreakdownCell>> byDeliveryType;
  final OrderBreakdownMode mode;
  final double totalRevenue;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final columnCount = deliveryTypes.length + 1; // +1 for source column
    final columnWidths = <int, TableColumnWidth>{
      0: const IntrinsicColumnWidth(), // source names fit content
    };
    for (var i = 1; i < columnCount; i++) {
      columnWidths[i] = const IntrinsicColumnWidth();
    }

    return Table(
      columnWidths: columnWidths,
      children: [
        _headerRow(headerStyle, theme),
        for (final source in sources)
          _sourceRow(source, theme),
        _totalsRow(theme),
      ],
    );
  }

  TableRow _headerRow(TextStyle? style, ThemeData theme) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      children: [
        _headerCell(SharedLabels.todaySalesOrderBreakdownSourceHeader, style),
        for (final dt in deliveryTypes) _headerCell(dt, style),
      ],
    );
  }

  Widget _headerCell(String text, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }

  TableRow _sourceRow(String source, ThemeData theme) {
    final bodyStyle = theme.textTheme.bodyMedium;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            source,
            style: bodyStyle?.copyWith(fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final dt in deliveryTypes)
          _cell(source, dt, bodyStyle),
      ],
    );
  }

  Widget _cell(String source, String deliveryType, TextStyle? style) {
    final cell = byKey['$source\u0000$deliveryType'];
    if (cell == null) {
      return _paddedText('—', style?.copyWith(color: Colors.grey));
    }
    return _metricCell(
      cell.orderCount,
      cell.revenue,
      style,
    );
  }

  TableRow _totalsRow(ThemeData theme) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(SharedLabels.todaySalesOrderBreakdownTotal, style: style),
        ),
        for (final dt in deliveryTypes) _totalsCell(dt, style),
      ],
    );
  }

  /// Build a totals cell for a delivery-type column. Looks up the
  /// column's cells via [byDeliveryType] (direct match on `deliveryType`)
  /// instead of substring-matching composite keys (CQ-4 fix).
  Widget _totalsCell(String deliveryType, TextStyle? style) {
    final cellsForType = byDeliveryType[deliveryType] ?? const [];
    final count = cellsForType.fold<int>(0, (s, c) => s + c.orderCount);
    final revenue = cellsForType.fold<double>(0, (s, c) => s + c.revenue);
    return _metricCell(count, revenue, style);
  }

  /// Render a count + (optional) revenue + (optional) share-of-total cell.
  Widget _metricCell(int count, double revenue, TextStyle? style) {
    final parts = <String>['$count'];
    if (mode == OrderBreakdownMode.countRevenue ||
        mode == OrderBreakdownMode.countRevenueShare) {
      parts.add(formatVND(revenue));
    }
    if (mode == OrderBreakdownMode.countRevenueShare) {
      parts.add(_formatPercent(revenue, totalRevenue));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in parts)
            Text(p, style: style, textAlign: TextAlign.end),
        ],
      ),
    );
  }

  Widget _paddedText(String text, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(text, style: style, textAlign: TextAlign.end),
    );
  }

  String _formatPercent(double value, double total) {
    if (total == 0) return '0%';
    final pct = (value / total) * 100;
    final rounded = (pct * 10).roundToDouble() / 10;
    final text = rounded.toStringAsFixed(rounded % 1 == 0 ? 0 : 1);
    return '$text%';
  }
}