import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/dashboard/dashboard_metrics_provider.dart';
import '../../providers/dashboard/period_summary_providers.dart';
import '../../shared/labels/shared.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/day_tab_body.dart';
import 'widgets/period_tab_body.dart';

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
    with WidgetsBindingObserver, AutoRefreshMixin, SingleTickerProviderStateMixin {
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

  @override
  String screenRoutePath() => '/today-sales';

  @override
  void invalidateProviders() {
    ref.invalidate(todaySummaryProvider);
    ref.invalidate(dateSummaryProvider);
  }

  @override
  void initState() {
    super.initState();
    // Tab changes drive `isDayTab` and the AppBar title, so rebuild on every
    // tab transition (Mn-4). Removed in `dispose` to avoid leaking the
    // listener once the controller is disposed.
    _tabController.addListener(_onTabChanged);
    initAutoRefresh();
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    disposeAutoRefresh();
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
        title: Text(isToday
            ? SharedLabels.todaySalesTitle
            : formatDisplayDate(parseApiDate(_selectedDate))),
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
            onPressed: onAutoRefreshTriggered,
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