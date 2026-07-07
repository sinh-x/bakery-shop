import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/features/expenses/expense_constants.dart';
import 'package:bakery_app/features/expenses/widgets/expense_filter_card.dart';
import 'package:bakery_app/features/expenses/widgets/expense_history_card.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/mixins/auto_refresh_mixin.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
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
  bool _deleting = false;
  bool _initialHistoryLoading = true;
  DateTime? _since;
  DateTime? _until;
  ExpenseDateFilterMode _dateFilterMode = ExpenseDateFilterMode.range;
  String _filterCategory = '';
  String _filterPaidByName = '';
  String _filterLoggedByName = '';
  String _filterPaymentSource = '';
  ExpenseDebtStatusFilter _filterDebtStatus = ExpenseDebtStatusFilter.all;
  List<BakeryEvent> _history = <BakeryEvent>[];

  @override
  String screenRoutePath() => '/expenses';

  @override
  void invalidateProviders() {}

  @override
  void initState() {
    super.initState();
    onAutoRefresh = _refreshHistory;
    final today = DateTime.now();
    _until = DateTime(today.year, today.month, today.day);
    _since = _until!.subtract(const Duration(days: 6));
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshHistory());
    initAutoRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  void _setDeleting(bool value) {
    if (!mounted) return;
    setState(() => _deleting = value);
  }

  void _setHistory(List<BakeryEvent> events) {
    if (!mounted) return;
    setState(() {
      _history = events;
      _initialHistoryLoading = false;
    });
  }

  void _setInitialHistoryLoading(bool value) {
    if (!mounted) return;
    setState(() => _initialHistoryLoading = value);
  }

  void _clearFilterState() {
    if (!mounted) return;
    setState(() {
      _since = null;
      _until = null;
      _dateFilterMode = ExpenseDateFilterMode.range;
      _filterCategory = '';
      _filterPaidByName = '';
      _filterLoggedByName = '';
      _filterPaymentSource = '';
      _filterDebtStatus = ExpenseDebtStatusFilter.all;
      _searchCtrl.clear();
    });
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> _paidByFilterOptions() {
    final names =
        _history
            .map(ExpenseEventMapper.fromEvent)
            .whereType<ExpenseEventData>()
            .map((event) => event.paidByName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_filterPaidByName.isNotEmpty && !names.contains(_filterPaidByName)) {
      names.insert(0, _filterPaidByName);
    }
    return names;
  }

  List<String> _loggedByFilterOptions() {
    final names =
        _history
            .map(ExpenseEventMapper.fromEvent)
            .whereType<ExpenseEventData>()
            .map((event) => event.loggedBy.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_filterLoggedByName.isNotEmpty && !names.contains(_filterLoggedByName)) {
      names.insert(0, _filterLoggedByName);
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.expenseTitle),
        actions: [
          if (widget.onOpenDebts != null)
            IconButton(
              onPressed: widget.onOpenDebts,
              tooltip: VN.debtListTitle,
              icon: const Icon(Icons.account_balance),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        tooltip: VN.expenseAddAction,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            VN.expenseHistorySection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ExpenseFilterCard(
            searchCtrl: _searchCtrl,
            since: _since,
            until: _until,
            dateFilterMode: _dateFilterMode,
            categories: expenseCategories,
            paymentSources: expensePaymentSources,
            paidByNames: _paidByFilterOptions(),
            loggedByNames: _loggedByFilterOptions(),
            filterCategory: _filterCategory,
            filterPaymentSource: _filterPaymentSource,
            filterPaidByName: _filterPaidByName,
            filterLoggedByName: _filterLoggedByName,
            filterDebtStatus: _filterDebtStatus,
            onFilterDebtStatusChanged: (value) {
              setState(() => _filterDebtStatus = value);
              _refreshHistory();
            },
            onDateFilterModeChanged: (value) => setState(() {
              _dateFilterMode = value;
              if (value == ExpenseDateFilterMode.single && _since != null) {
                _until = _since;
              }
            }),
            onPickDate: _pickDate,
            onFilterCategoryChanged: (value) {
              setState(() => _filterCategory = value);
              _refreshHistory();
            },
            onFilterPaymentSourceChanged: (value) {
              setState(() => _filterPaymentSource = value);
              _refreshHistory();
            },
            onFilterPaidByNameChanged: (value) {
              setState(() => _filterPaidByName = value);
              _refreshHistory();
            },
            onFilterLoggedByNameChanged: (value) {
              setState(() => _filterLoggedByName = value);
              _refreshHistory();
            },
            onClearFilters: _clearFilters,
            onApplyFilters: _refreshHistory,
            formatDate: _isoDate,
          ),
          const SizedBox(height: 8),
          if (_initialHistoryLoading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            ..._history.map(
              (e) => ExpenseHistoryCard(
                event: e,
                onEdit: _deleting ? null : () => _openEdit(e),
                onDelete: _deleting ? null : () => _confirmDelete(e.id),
              ),
            ),
          if (!_initialHistoryLoading && _history.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(VN.expenseNoHistory),
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
    final shouldToggleInitialLoading = _initialHistoryLoading;
    final debtStatusApi = expenseDebtStatusFilterApiValue(_filterDebtStatus);
    try {
      final loader = widget.loadHistory;
      final events = await (loader != null
          ? loader(
              since: _since == null ? null : _localDayStartIso(_since!),
              until: _until == null ? null : _localDayEndIso(_until!),
              category: _filterCategory,
              paymentMethod: null,
              paymentSource: _filterPaymentSource,
              paidByName: _filterPaidByName,
              loggedBy: _filterLoggedByName,
              searchText: _searchCtrl.text.trim(),
              debtStatus: debtStatusApi.isEmpty ? null : debtStatusApi,
            )
          : ref
                 .read(eventsProvider.notifier)
                 .loadExpenseHistory(
                   since: _since == null ? null : _localDayStartIso(_since!),
                   until: _until == null ? null : _localDayEndIso(_until!),
                   category: _filterCategory,
                   paymentMethod: null,
                   paymentSource: _filterPaymentSource,
                   paidByName: _filterPaidByName,
                   loggedBy: _filterLoggedByName,
                   searchText: _searchCtrl.text.trim(),
                   debtStatus: debtStatusApi.isEmpty ? null : debtStatusApi,
                 ));
      _setHistory(events);
    } catch (e) {
      if (shouldToggleInitialLoading) {
        _setInitialHistoryLoading(false);
      }
      if (mounted) {
        showTopSnackBar(
          context,
          e is DioException ? (e.message ?? VN.apiError) : VN.apiError,
        );
      }
    }
  }

  Future<void> _confirmDelete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(VN.deleteEvent),
        content: const Text(VN.deleteEventConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(VN.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(VN.deleteEvent),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _setDeleting(true);
    try {
      final custom = widget.deleteExpense;
      if (custom != null) {
        await custom(id);
      } else {
        final deletedBy = ref.read(loggedByProvider);
        await ref.read(eventsProvider.notifier).deleteEvent(id, deletedBy: deletedBy);
      }
      await _refreshHistory();
      if (mounted) showTopSnackBar(context, VN.eventDeleted);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          e is DioException ? (e.message ?? VN.apiError) : VN.apiError,
        );
      }
    } finally {
      _setDeleting(false);
    }
  }

  void _clearFilters() {
    _clearFilterState();
    _refreshHistory();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    if (_dateFilterMode == ExpenseDateFilterMode.single) {
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDate: _since ?? _until ?? now,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _since = picked;
        _until = picked;
      });
      return;
    }

    final start = _since ?? _until ?? now.subtract(const Duration(days: 6));
    final end = _until ?? _since ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _since = picked.start;
      _until = picked.end;
    });
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
