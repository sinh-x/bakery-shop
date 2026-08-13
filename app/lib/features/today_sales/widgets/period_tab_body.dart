import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order.dart';
import '../../../data/models/period_summary.dart';
import '../../../providers/dashboard/period_summary_providers.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/widgets/section_title.dart';
import '../../dashboard/widgets/today_order_list.dart';
import 'revenue_summary_section.dart';

/// Week/Month tab body for the Today Sales screen (DG-386 Phase 6 / FR1,
/// FR2 / AC1, AC2, AC7).
///
/// Renders the period-aggregated summary for a [PeriodQuery] (week or month).
/// Reuses [RevenueSummarySection] for the revenue/payment/cash-source cards
/// because the [PeriodSummary] metric fields are identical in shape to
/// `TodaySummary`. The product/expense/cashflow sections are placeholder
/// `SectionTitle`-only blocks that will be filled by Phases 7–9.
///
/// Period navigation (prev/next) is owned by the parent [TodaySalesScreen]
/// and flows in via [query] and [onNavigate]. Switching the tab or navigating
/// to a different week/month produces a new [PeriodQuery] and triggers a
/// fresh fetch (AC7).
class PeriodTabBody extends ConsumerWidget {
  const PeriodTabBody({
    super.key,
    required this.query,
    required this.onNavigate,
  });

  final PeriodQuery query;

  final void Function(DateTime newAnchor) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(periodSummaryProvider(query));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            SharedLabels.errorLoading,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (summary) => _PeriodTabContent(
        summary: summary,
        query: query,
        onNavigate: onNavigate,
      ),
    );
  }
}

class _PeriodTabContent extends StatelessWidget {
  const _PeriodTabContent({
    required this.summary,
    required this.query,
    required this.onNavigate,
  });

  final PeriodSummary summary;
  final PeriodQuery query;
  final void Function(DateTime newAnchor) onNavigate;

  bool get _isWeek => query.period == 'week';

  DateTime get _anchor => parseApiDate(query.date) ?? DateTime.now();

  /// Shifts the anchor by one week (±7 days) or one month (±1 month) so the
  /// backend re-derives the new period window from the new anchor.
  DateTime _shift(int direction) {
    final anchor = _anchor;
    if (_isWeek) {
      return anchor.add(Duration(days: 7 * direction));
    }
    final newMonth = anchor.month + direction;
    if (newMonth > 12) {
      return DateTime(anchor.year + 1, 1, anchor.day);
    } else if (newMonth < 1) {
      return DateTime(anchor.year - 1, 12, anchor.day);
    }
    return DateTime(anchor.year, newMonth, anchor.day);
  }

  String get _periodLabel {
    if (_isWeek) {
      final start = parseApiDate(summary.startDate);
      final end = parseApiDate(summary.endDate);
      if (start == null || end == null) return SharedLabels.todaySalesTabWeek;
      return '${formatDisplayDate(start)} - ${formatDisplayDate(end)}';
    }
    final start = parseApiDate(summary.startDate);
    if (start == null) return SharedLabels.todaySalesTabMonth;
    return '${start.month}/${start.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PeriodNavHeader(
          label: _periodLabel,
          onPrev: () => onNavigate(_shift(-1)),
          onNext: () => onNavigate(_shift(1)),
        ),
        const SizedBox(height: 16),
        RevenueSummarySection(
          totalRevenue: summary.revenue,
          orderCount: summary.orderCount,
          cashTotal: summary.cashTotal,
          bankTransferTotal: summary.bankTransferTotal,
          cashInTotal: summary.cashInTotal,
          cashOutTotal: summary.cashOutTotal,
        ),
        const SizedBox(height: 20),
        // Placeholder sections for Phases 7–9. Kept as titled stubs so the
        // screen compiles and the layout is ready for the upcoming widgets.
        const _PlaceholderSection(title: 'Phân tích sản phẩm'),
        const SizedBox(height: 20),
        const _PlaceholderSection(title: 'Chi phí'),
        const SizedBox(height: 20),
        const _PlaceholderSection(title: 'Dòng tiền'),
        const SizedBox(height: 20),
        _PeriodOrderListSection(orders: summary.orders),
      ],
    );
  }
}

/// Prev/next navigation header for the week/month tabs (FR1 / AC1, AC2).
class _PeriodNavHeader extends StatelessWidget {
  const _PeriodNavHeader({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: SharedLabels.back,
          onPressed: onPrev,
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: SharedLabels.back,
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Placeholder section used until Phases 7–9 build the real widgets. Keeps
/// the screen compiling and the layout reserved.
class _PlaceholderSection extends StatelessWidget {
  const _PlaceholderSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: title),
        const SizedBox(height: 8),
        Text(
          SharedLabels.loading,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }
}

/// Order-list section for the week/month tabs. Renders the orders aggregated
/// within the period using the same [TodayOrderList] grouping as the day tab.
class _PeriodOrderListSection extends StatelessWidget {
  const _PeriodOrderListSection({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesOrderListSection),
        const SizedBox(height: 8),
        TodayOrderList(orders: orders),
      ],
    );
  }
}