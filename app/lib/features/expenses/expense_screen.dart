import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/expense_constants.dart';
import 'package:bakery_app/features/expenses/widgets/expense_filter_card.dart';
import 'package:bakery_app/features/expenses/widgets/expense_history_card.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key, this.deleteExpense, this.loadHistory});

  final Future<void> Function(int eventId)? deleteExpense;
  final Future<List<BakeryEvent>> Function({
    String? since,
    String? until,
    String? category,
    String? paymentMethod,
    String? staffName,
    String? searchText,
  })?
  loadHistory;

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  final _searchCtrl = TextEditingController();
  final _filterStaffCtrl = TextEditingController();
  bool _deleting = false;
  bool _initialHistoryLoading = true;
  DateTime? _since;
  DateTime? _until;
  String _filterCategory = '';
  String _filterPaymentMethod = '';
  String _filterStaffName = '';
  List<BakeryEvent> _history = <BakeryEvent>[];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _until = DateTime(today.year, today.month, today.day);
    _since = _until!.subtract(const Duration(days: 6));
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshHistory());
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
      _filterCategory = '';
      _filterPaymentMethod = '';
      _filterStaffName = '';
      _filterStaffCtrl.clear();
      _searchCtrl.clear();
    });
  }

  void _setPickedDate(bool isSince, DateTime picked) {
    if (!mounted) return;
    setState(() {
      if (isSince) {
        _since = picked;
      } else {
        _until = picked;
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _filterStaffCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(VN.expenseTitle)),
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
            filterStaffCtrl: _filterStaffCtrl,
            since: _since,
            until: _until,
            categories: expenseCategories,
            paymentMethods: expensePaymentMethods,
            filterCategory: _filterCategory,
            filterPaymentMethod: _filterPaymentMethod,
            onPickSince: () => _pickDate(true),
            onPickUntil: () => _pickDate(false),
            onFilterCategoryChanged: (value) =>
                setState(() => _filterCategory = value ?? ''),
            onFilterPaymentMethodChanged: (value) =>
                setState(() => _filterPaymentMethod = value ?? ''),
            onFilterStaffChanged: (value) => _filterStaffName = value,
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
          else ..._history.map(
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
    final updated = await context.push<bool>('/expenses/${event.id}/edit', extra: event);
    if (updated == true) {
      await _refreshHistory();
    }
  }

  Future<void> _refreshHistory() async {
    final shouldToggleInitialLoading = _initialHistoryLoading;
    try {
      final loader = widget.loadHistory;
      final events = await (loader != null
          ? loader(
              since: _since == null ? null : _isoDate(_since!),
              until: _until == null ? null : _isoDate(_until!),
              category: _filterCategory,
              paymentMethod: _filterPaymentMethod,
              staffName: _filterStaffName,
              searchText: _searchCtrl.text.trim(),
            )
          : ref.read(eventsProvider.notifier).loadExpenseHistory(
                since: _since == null ? null : _isoDate(_since!),
                until: _until == null ? null : _isoDate(_until!),
                category: _filterCategory,
                paymentMethod: _filterPaymentMethod,
                staffName: _filterStaffName,
                searchText: _searchCtrl.text.trim(),
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
        await ref.read(eventsProvider.notifier).deleteEvent(id);
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

  Future<void> _pickDate(bool isSince) async {
    final now = DateTime.now();
    final initial = isSince ? (_since ?? now) : (_until ?? now);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null) return;
    _setPickedDate(isSince, picked);
  }

  String _isoDate(DateTime input) =>
      '${input.year.toString().padLeft(4, '0')}-${input.month.toString().padLeft(2, '0')}-${input.day.toString().padLeft(2, '0')}';
}
