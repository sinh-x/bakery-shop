import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers/dashboard_metrics_provider.dart';
import '../../data/providers/period_summary_providers.dart';
import '../../shared/labels/shared.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/day_tab_body.dart';
import 'widgets/period_tab_body.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Today Sales screen (DG-374 Phase 2 / FR3, FR4 / AC5, AC6), refactored in
/// DG-386 Phase 6 to add a Ngày/Tuần/Tháng tab bar with week/month prev/next
/// navigation (FR1 / AC1, AC2, AC7).
///
/// - **Ngày tab**: keeps the pre-Phase-6 behavior, including the date picker
///   in the AppBar (today → `todaySummaryProvider`, historical →
///   `dateSummaryProvider(<date>)`).
/// - **Tuần tab**: shows the current week (Monday–Sunday) summary via
///   `periodSummaryProvider(week)`. Prev/next arrows navigate weeks.
/// - **Tháng tab**: shows the current month (1st–last day) summary via
///   `periodSummaryProvider(month)`. Prev/next arrows navigate months.
///
/// The screen is a thin orchestrator: tab state lives here, while each tab's
/// body is rendered by [DayTabBody] or [PeriodTabBody] (NF2 — screen ≤ 300
/// lines, each widget file ≤ 300 lines). The product breakdown, expense
/// summary, and cashflow summary section widgets are implemented and wired
/// into [PeriodTabBody] (DG-386 Phases 7–11 / FR1).
class TodaySalesScreen extends ConsumerStatefulWidget {
  const TodaySalesScreen({super.key});

  @override
  ConsumerState<TodaySalesScreen> createState() => _TodaySalesScreenState();
}

class _TodaySalesScreenState extends ConsumerState<TodaySalesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  /// Selected date for the Ngày tab (defaults to today). The date picker in
  /// the AppBar updates this and is only shown when the Ngày tab is active.
  String _selectedDate = formatApiDate(DateTime.now());

  /// Anchor date for the Tuần tab (week navigation).
  String _weekAnchor = formatApiDate(DateTime.now());

  /// Anchor date for the Tháng tab (month navigation).
  String _monthAnchor = formatApiDate(DateTime.now());

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = formatApiDate(picked));
    }
  }

  void _navigateWeek(DateTime newAnchor) {
    setState(() => _weekAnchor = formatApiDate(newAnchor));
  }

  void _navigateMonth(DateTime newAnchor) {
    setState(() => _monthAnchor = formatApiDate(newAnchor));
  }

  void _refreshAll() {
    ref.invalidate(todaySummaryProvider);
    ref.invalidate(dateSummaryProvider);
    // Invalidate the four period source families directly for each active
    // period query (day/week/month) so the Tuần/Tháng tabs refresh via the
    // AppBar refresh button. Riverpod invalidation propagates from a provider
    // to its dependents — not to the providers it `watch`es — so invalidating
    // the combined `periodReportDataProvider` would re-run it against the
    // still-cached source families and leave the tabs stale. Invalidating the
    // source families instead propagates correctly to
    // `periodReportDataProvider`. This mirrors the pull-to-refresh pattern in
    // `day_tab_body.dart`, extended to the week/month queries.
    final dayQuery = PeriodQuery(period: 'day', date: _selectedDate);
    final weekQuery = PeriodQuery(period: 'week', date: _weekAnchor);
    final monthQuery = PeriodQuery(period: 'month', date: _monthAnchor);
    for (final query in [dayQuery, weekQuery, monthQuery]) {
      ref.invalidate(periodSummaryProvider(query));
      ref.invalidate(productBreakdownProvider(query));
      ref.invalidate(expenseSummaryProvider(query));
      ref.invalidate(cashflowSummaryProvider(query));
    }
  }

  @override
  void initState() {
    super.initState();
    // Tab changes drive `isDayTab` and the AppBar title, so rebuild on every
    // tab transition (Mn-4). Removed in `dispose` to avoid leaking the
    // listener once the controller is disposed.
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _selectedDate == formatApiDate(DateTime.now());
    final isDayTab = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
        title: Text(
          isToday
              ? SharedLabels.todaySalesTitle
              : formatDisplayDate(parseApiDate(_selectedDate)),
        ),
        actions: [
          if (isDayTab)
            IconButton(
              icon: const Icon(Icons.calendar_today),
              tooltip: VN.chonNgay,
              onPressed: _pickDate,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: SharedLabels.lamMoi,
            onPressed: _refreshAll,
          ),
          const AppBarOverflowMenu(),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: SharedLabels.todaySalesTabDay),
            Tab(text: SharedLabels.todaySalesTabWeek),
            Tab(text: SharedLabels.todaySalesTabMonth),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            DayTabBody(selectedDate: _selectedDate, isToday: isToday),
            PeriodTabBody(
              query: PeriodQuery(period: 'week', date: _weekAnchor),
              onNavigate: _navigateWeek,
            ),
            PeriodTabBody(
              query: PeriodQuery(period: 'month', date: _monthAnchor),
              onNavigate: _navigateMonth,
            ),
          ],
        ),
      ),
    );
  }
}
