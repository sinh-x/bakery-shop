import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/widgets/expense_filter_card.dart';
import 'package:bakery_app/features/expenses/widgets/expense_form_card.dart';
import 'package:bakery_app/features/expenses/widgets/expense_history_card.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'expense_screen_logic.dart';

class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({
    super.key,
    this.saveExpense,
    this.updateExpense,
    this.deleteExpense,
    this.loadHistory,
  });

  final Future<void> Function(ExpenseEventData data)? saveExpense;
  final Future<void> Function(int eventId, ExpenseEventData data)?
  updateExpense;
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
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _staffCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _filterStaffCtrl = TextEditingController();
  bool _loading = false;
  bool _editing = false;
  int? _editingId;
  DateTime? _since;
  DateTime? _until;
  String _category = VN.expenseCategoryIngredient;
  String _paymentMethod = VN.methodCash;
  String _filterCategory = '';
  String _filterPaymentMethod = '';
  String _filterStaffName = '';
  List<BakeryEvent> _history = <BakeryEvent>[];

  static const _categories = <String>[
    VN.expenseCategoryIngredient,
    VN.expenseCategoryPackaging,
    VN.expenseCategoryDelivery,
    VN.expenseCategoryUtilities,
    VN.expenseCategoryTools,
    VN.expenseCategoryRepair,
    VN.expenseCategorySalaryAllowance,
    VN.expenseCategoryOther,
  ];
  static const _paymentMethods = <String>[VN.methodCash, VN.methodTransfer];

  @override
  void initState() {
    super.initState();
    try {
      _staffCtrl.text = ref.read(loggedByProvider);
    } catch (_) {
      _staffCtrl.text = '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshHistory());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _vendorCtrl.dispose();
    _noteCtrl.dispose();
    _staffCtrl.dispose();
    _searchCtrl.dispose();
    _filterStaffCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(VN.expenseTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            VN.expenseFormSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ExpenseFormCard(
            formKey: _formKey,
            amountCtrl: _amountCtrl,
            vendorCtrl: _vendorCtrl,
            noteCtrl: _noteCtrl,
            staffCtrl: _staffCtrl,
            categories: _categories,
            paymentMethods: _paymentMethods,
            category: _category,
            paymentMethod: _paymentMethod,
            loading: _loading,
            editing: _editing,
            onCategoryChanged: (value) =>
                setState(() => _category = value ?? _category),
            onPaymentMethodChanged: (value) =>
                setState(() => _paymentMethod = value ?? _paymentMethod),
            onCancelEdit: _cancelEdit,
            onSave: _save,
            amountValidator: _validateAmount,
          ),
          const SizedBox(height: 20),
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
            categories: _categories,
            paymentMethods: _paymentMethods,
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
          ..._history.map(
            (e) => ExpenseHistoryCard(
              event: e,
              onEdit: () => _startEdit(e),
              onDelete: () => _confirmDelete(e.id),
            ),
          ),
          if (_history.isEmpty)
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

  String? _validateAmount(String? value) {
    final raw = (value ?? '').trim();
    final parsed = int.tryParse(raw);
    if (raw.isEmpty || parsed == null || parsed <= 0) {
      return VN.expenseAmountValidationMessage;
    }
    return null;
  }
}
