import 'package:flutter/material.dart';

import '../../../data/models/order_breakdown.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';

/// Display mode for the order-breakdown matrix (DG-391 Phase 3 / FR2 / AC2).
///
/// Each mode selects which metric is rendered in each matrix cell:
/// - [count] — order count only.
/// - [countRevenue] — order count + revenue (VND). This is the default.
/// - [countRevenueShare] — order count + revenue + revenue share (% of the
///   period's total revenue across all cells).
enum _BreakdownMode {
  count,
  countRevenue,
  countRevenueShare,
}

/// Order-breakdown section for the Today Sales screen Tuần/Tháng tabs
/// (DG-391 Phase 3 / FR1, FR2, FR6, FR7 / AC1, AC2).
///
/// Renders a source × delivery_type matrix from the cells returned by
/// `GET /api/reports/order-breakdown` (Phase 2). A dropdown switches between
/// the three display modes ([_BreakdownMode]). Rows are sources in a fixed
/// business-defined order (FR7); columns are the distinct delivery types
/// present in the data. A trailing totals row sums order count and revenue.
///
/// The matrix is wrapped in a horizontal [SingleChildScrollView] so it does
/// not overflow on narrow phones (NFR1). All user-facing text uses
/// [SharedLabels] (NFR2 — no inline VN strings).
///
/// The widget is a [StatefulWidget] only to hold the selected dropdown mode;
/// the breakdown data is supplied by the caller (the owning tab body owns the
/// `orderBreakdownProvider` lifecycle). When [breakdown] is `null` or has no
/// cells the empty state is rendered.
class OrderBreakdownSection extends StatefulWidget {
  const OrderBreakdownSection({
    super.key,
    required this.breakdown,
  });

  /// Order-breakdown report to render. `null` indicates the caller is still
  /// loading or has no data; the empty state is shown in that case.
  final OrderBreakdown? breakdown;

  @override
  State<OrderBreakdownSection> createState() => _OrderBreakdownSectionState();
}

class _OrderBreakdownSectionState extends State<OrderBreakdownSection> {
  _BreakdownMode _mode = _BreakdownMode.countRevenue;

  @override
  Widget build(BuildContext context) {
    final cells = widget.breakdown?.cells ?? const <OrderBreakdownCell>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesOrderBreakdownSection),
        const SizedBox(height: 8),
        _ModeDropdown(
          mode: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: 8),
        if (cells.isEmpty)
          const _EmptyState()
        else
          _BreakdownMatrix(cells: cells, mode: _mode),
      ],
    );
  }
}

/// Dropdown that switches the breakdown display mode (FR2 / AC2).
class _ModeDropdown extends StatelessWidget {
  const _ModeDropdown({required this.mode, required this.onChanged});

  final _BreakdownMode mode;
  final ValueChanged<_BreakdownMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DropdownButton<_BreakdownMode>(
        value: mode,
        isExpanded: false,
        items: const [
          DropdownMenuItem(
            value: _BreakdownMode.count,
            child: Text(SharedLabels.todaySalesOrderBreakdownModeCount),
          ),
          DropdownMenuItem(
            value: _BreakdownMode.countRevenue,
            child: Text(
                SharedLabels.todaySalesOrderBreakdownModeCountRevenue),
          ),
          DropdownMenuItem(
            value: _BreakdownMode.countRevenueShare,
            child: Text(
                SharedLabels.todaySalesOrderBreakdownModeCountRevenueShare),
          ),
        ],
        onChanged: (m) {
          if (m != null) onChanged(m);
        },
      ),
    );
  }
}

/// The source × delivery_type matrix (FR7 / NFR1).
///
/// Sources are ordered per the fixed business priority
/// (`_sourcePriority`); any source not in the priority list sorts
/// alphabetically after the known ones. Delivery types use their natural
/// occurrence order in the data (alphabetically sorted for determinism).
class _BreakdownMatrix extends StatelessWidget {
  const _BreakdownMatrix({required this.cells, required this.mode});

  final List<OrderBreakdownCell> cells;
  final _BreakdownMode mode;

  /// Fixed business-defined source ordering (FR7). Sources not listed here
  /// are appended alphabetically.
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

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _MatrixTable(
            sources: sources,
            deliveryTypes: deliveryTypes,
            byKey: byKey,
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

/// Renders the matrix as a [Table] with a leading source column, one column
/// per delivery type, and a trailing totals row.
class _MatrixTable extends StatelessWidget {
  const _MatrixTable({
    required this.sources,
    required this.deliveryTypes,
    required this.byKey,
    required this.mode,
    required this.totalRevenue,
    required this.totalCount,
  });

  final List<String> sources;
  final List<String> deliveryTypes;
  final Map<String, OrderBreakdownCell> byKey;
  final _BreakdownMode mode;
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
    final parts = <String>['${cell.orderCount}'];
    if (mode == _BreakdownMode.countRevenue ||
        mode == _BreakdownMode.countRevenueShare) {
      parts.add(formatVND(cell.revenue));
    }
    if (mode == _BreakdownMode.countRevenueShare) {
      parts.add(_formatPercent(cell.revenue, totalRevenue));
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

  Widget _totalsCell(String deliveryType, TextStyle? style) {
    final cellsForType = byKey.entries
        .where((e) => e.key.contains('\u0000$deliveryType'))
        .map((e) => e.value)
        .toList();
    final count = cellsForType.fold<int>(0, (s, c) => s + c.orderCount);
    final revenue = cellsForType.fold<double>(0, (s, c) => s + c.revenue);
    final parts = <String>['$count'];
    if (mode == _BreakdownMode.countRevenue ||
        mode == _BreakdownMode.countRevenueShare) {
      parts.add(formatVND(revenue));
    }
    if (mode == _BreakdownMode.countRevenueShare) {
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

/// Empty-state placeholder shown when the period has no order-breakdown cells
/// (e.g. no orders in the selected week/month). Mirrors the product-breakdown
/// empty-state styling.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  SharedLabels.todaySalesOrderBreakdownEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}