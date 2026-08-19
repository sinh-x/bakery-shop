import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/data/models/expense_category.dart';
import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/features/expenses/expense_constants.dart';
import 'package:bakery_app/features/expenses/providers/expense_filter_notifier.dart';
import 'package:bakery_app/features/expenses/widgets/expense_filter_card.dart';
import 'package:bakery_app/features/expenses/widgets/expense_history_card.dart';
import 'package:bakery_app/data/providers/events_provider.dart';
import 'package:bakery_app/shared/providers/logged_by_provider.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/mixins/auto_refresh_mixin.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({
    super.key,
    this.deleteExpense,
    this.loadHistory,
    this.onOpenDebts,
  });

  final Future<void> Function(int eventId)? deleteExpense;
  final Future<List<BakeryEvent>> Function({
    String? since,
    String? until,
    String? category,
    String? paymentMethod,
    String? paymentSource,
    String? staffName,
    String? paidByName,
    String? loggedBy,
    String? searchText,
    String? debtStatus,
    String? subcategory,
  })?
  loadHistory;

  /// Optional callback invoked when the user taps the "Danh sách công nợ"
  /// action in the app bar. When ``null`` the action is hidden (used by
  /// tests that do not wire the debts route).
  final VoidCallback? onOpenDebts;

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  final _searchCtrl = TextEditingController();

  @override
  String screenRoutePath() => '/expenses';

  @override
  void invalidateProviders() {}

  @override
  void initState() {
    super.initState();
    onAutoRefresh = _refreshHistory;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshHistory());
    initAutoRefresh();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    ref
        .read(expenseFilterProvider.notifier)
        .setSearchText(_searchCtrl.text);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> _paidByFilterOptions(List<BakeryEvent> history, String current) {
    final names =
        history
            .map(ExpenseEventMapper.fromEvent)
            .whereType<ExpenseEventData>()
            .map((event) => event.paidByName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (current.isNotEmpty && !names.contains(current)) {
      names.insert(0, current);
    }
    return names;
  }

  List<String> _loggedByFilterOptions(List<BakeryEvent> history, String current) {
    final names =
        history
            .map(ExpenseEventMapper.fromEvent)
            .whereType<ExpenseEventData>()
            .map((event) => event.loggedBy.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (current.isNotEmpty && !names.contains(current)) {
      names.insert(0, current);
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(expenseFilterProvider);
    final filterNotifier = ref.read(expenseFilterProvider.notifier);
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final categoryTree = categoriesAsync.whenOrNull<List<ExpenseCategory>>(
          data: (tree) => tree,
        ) ??
        const <ExpenseCategory>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text(ExpensesLabels.expenseTitle),
        actions: [
          if (widget.onOpenDebts != null)
            IconButton(
              onPressed: widget.onOpenDebts,
              tooltip: ExpensesLabels.debtListTitle,
              icon: const Icon(Icons.account_balance),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        tooltip: ExpensesLabels.expenseAddAction,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            ExpensesLabels.expenseHistorySection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ExpenseFilterCard(
            searchCtrl: _searchCtrl,
            since: filter.since,
            until: filter.until,
            dateFilterMode: filter.dateFilterMode,
            categories: expenseCategories,
            paymentSources: expensePaymentSources,
            paidByNames: _paidByFilterOptions(filter.history, filter.filterPaidByName),
            loggedByNames: _loggedByFilterOptions(filter.history, filter.filterLoggedByName),
            filterCategory: filter.filterCategory,
            filterPaymentSource: filter.filterPaymentSource,
            filterPaidByName: filter.filterPaidByName,
            filterLoggedByName: filter.filterLoggedByName,
            filterDebtStatus: filter.filterDebtStatus,
            onFilterDebtStatusChanged: (value) {
              filterNotifier.setDebtStatus(value);
              _refreshHistory();
            },
            categoryTree: categoryTree,
            filterSubcategory: filter.filterSubcategory,
            onFilterSubcategoryChanged: (value) {
              filterNotifier.setSubcategory(value);
              _refreshHistory();
            },
            onDateFilterModeChanged: filterNotifier.setDateFilterMode,
            onPickDate: _pickDate,
            onFilterCategoryChanged: (value) {
              filterNotifier.setCategory(value);
              _refreshHistory();
            },
            onFilterPaymentSourceChanged: (value) {
              filterNotifier.setPaymentSource(value);
              _refreshHistory();
            },
            onFilterPaidByNameChanged: (value) {
              filterNotifier.setPaidByName(value);
              _refreshHistory();
            },
            onFilterLoggedByNameChanged: (value) {
              filterNotifier.setLoggedByName(value);
              _refreshHistory();
            },
            onClearFilters: _clearFilters,
            onApplyFilters: _refreshHistory,
            formatDate: _isoDate,
          ),
          const SizedBox(height: 8),
          if (filter.initialHistoryLoading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            ...filter.history.map(
              (e) => ExpenseHistoryCard(
                key: ValueKey(e.id),
                event: e,
                onEdit: filter.deleting ? null : () => _openEdit(e),
                onDelete: filter.deleting ? null : () => _confirmDelete(e.id),
              ),
            ),
          if (!filter.initialHistoryLoading && filter.history.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(ExpensesLabels.expenseNoHistory),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openAdd() async {
    final created = await context.push<bool>('/expenses/new');
    if (created == true) {
      await _refreshHistory();
    }
  }

  Future<void> _openEdit(BakeryEvent event) async {
    final updated = await context.push<bool>(
      '/expenses/${event.id}/edit',
      extra: event,
    );
    if (updated == true) {
      await _refreshHistory();
    }
  }

  Future<void> _refreshHistory() async {
    final filter = ref.read(expenseFilterProvider);
    final notifier = ref.read(expenseFilterProvider.notifier);
    final shouldToggleInitialLoading = filter.initialHistoryLoading;
    final debtStatusApi = expenseDebtStatusFilterApiValue(filter.filterDebtStatus);
    try {
      final loader = widget.loadHistory;
      final events = await (loader != null
          ? loader(
              since: filter.since == null ? null : _localDayStartIso(filter.since!),
              until: filter.until == null ? null : _localDayEndIso(filter.until!),
              category: filter.filterCategory,
              paymentMethod: null,
              paymentSource: filter.filterPaymentSource,
              paidByName: filter.filterPaidByName,
              loggedBy: filter.filterLoggedByName,
              searchText: _searchCtrl.text.trim(),
              debtStatus: debtStatusApi.isEmpty ? null : debtStatusApi,
              subcategory: filter.filterSubcategory,
            )
          : ref
                  .read(eventsProvider.notifier)
                  .loadExpenseHistory(
                     since: filter.since == null ? null : _localDayStartIso(filter.since!),
                     until: filter.until == null ? null : _localDayEndIso(filter.until!),
                     category: filter.filterCategory,
                     paymentMethod: null,
                     paymentSource: filter.filterPaymentSource,
                     paidByName: filter.filterPaidByName,
                     loggedBy: filter.filterLoggedByName,
                     searchText: _searchCtrl.text.trim(),
                     debtStatus: debtStatusApi.isEmpty ? null : debtStatusApi,
                     subcategory: filter.filterSubcategory,
                   ));
      notifier.setHistory(events);
    } catch (e) {
      if (shouldToggleInitialLoading) {
        notifier.setInitialHistoryLoading(false);
      }
      if (mounted) {
        showTopSnackBar(
          context,
          e is DioException ? (e.message ?? SharedLabels.apiError) : SharedLabels.apiError,
        );
      }
    }
  }

  Future<void> _confirmDelete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(EventsLabels.deleteEvent),
        content: const Text(EventsLabels.deleteEventConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(BlanksLabels.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(EventsLabels.deleteEvent),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final notifier = ref.read(expenseFilterProvider.notifier);
    notifier.setDeleting(true);
    try {
      final custom = widget.deleteExpense;
      if (custom != null) {
        await custom(id);
      } else {
        final deletedBy = ref.read(loggedByProvider);
        await ref.read(eventsProvider.notifier).deleteEvent(id, deletedBy: deletedBy);
      }
      await _refreshHistory();
      if (mounted) showTopSnackBar(context, EventsLabels.eventDeleted);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          e is DioException ? (e.message ?? SharedLabels.apiError) : SharedLabels.apiError,
        );
      }
    } finally {
      notifier.setDeleting(false);
    }
  }

  void _clearFilters() {
    ref.read(expenseFilterProvider.notifier).clearFilters();
    _searchCtrl.clear();
    _refreshHistory();
  }

  Future<void> _pickDate() async {
    final filter = ref.read(expenseFilterProvider);
    final notifier = ref.read(expenseFilterProvider.notifier);
    final now = DateTime.now();
    if (filter.dateFilterMode == ExpenseDateFilterMode.single) {
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDate: filter.since ?? filter.until ?? now,
      );
      if (picked == null || !mounted) return;
      notifier.setSingleDate(picked);
      return;
    }

    final start = filter.since ?? filter.until ?? now.subtract(const Duration(days: 6));
    final end = filter.until ?? filter.since ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (picked == null || !mounted) return;
    notifier.setDateRange(picked.start, picked.end);
  }

  String _isoDate(DateTime input) => formatApiDate(input);

  String _localDayStartIso(DateTime input) {
    final start = DateTime(input.year, input.month, input.day);
    return '${_isoDate(start)}T00:00:00';
  }

  String _localDayEndIso(DateTime input) {
    return '${_isoDate(input)}T23:59:59.999';
  }
}