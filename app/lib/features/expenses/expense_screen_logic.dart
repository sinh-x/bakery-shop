part of 'expense_screen.dart';

extension _ExpenseScreenLogic on _ExpenseScreenState {
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null || _category!.isEmpty) return;
    final amount = int.parse(_amountCtrl.text.trim());
    final payload = ExpenseEventData(
      amountVnd: amount,
      category: _category!,
      paymentMethod: _paymentMethod,
      vendor: _vendorCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      staffName: _staffCtrl.text.trim(),
    );
    _setLoading(true);
    try {
      if (_editing && _editingId != null) {
        await _runUpdate(_editingId!, payload);
        if (mounted) showTopSnackBar(context, VN.eventUpdated);
      } else {
        await _runSave(payload);
        if (mounted) showTopSnackBar(context, VN.eventLogged);
      }
      await ref.read(loggedByProvider.notifier).setName(payload.staffName);
      await _refreshHistory();
      _clearForm();
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          e is DioException ? (e.message ?? VN.apiError) : VN.apiError,
        );
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _refreshHistory() async {
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
          : ref
                .read(eventsProvider.notifier)
                .loadExpenseHistory(
                  since: _since == null ? null : _isoDate(_since!),
                  until: _until == null ? null : _isoDate(_until!),
                  category: _filterCategory,
                  paymentMethod: _filterPaymentMethod,
                  staffName: _filterStaffName,
                  searchText: _searchCtrl.text.trim(),
                ));
      _setHistory(events);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          e is DioException ? (e.message ?? VN.apiError) : VN.apiError,
        );
      }
    }
  }

  Future<void> _runSave(ExpenseEventData data) async {
    final custom = widget.saveExpense;
    if (custom != null) return custom(data);
    await ref
        .read(eventsProvider.notifier)
        .logEvent(
          summary: _summary(data),
          type: expenseType,
          loggedBy: data.staffName,
          data: ExpenseEventMapper.toDataMap(data),
        );
  }

  Future<void> _runUpdate(int id, ExpenseEventData data) async {
    final custom = widget.updateExpense;
    if (custom != null) return custom(id, data);
    await ref
        .read(eventsProvider.notifier)
        .updateEvent(
          id: id,
          summary: _summary(data),
          loggedBy: data.staffName,
          data: ExpenseEventMapper.toDataMap(data),
        );
  }

  void _startEdit(BakeryEvent event) {
    final data = ExpenseEventMapper.fromEvent(event);
    if (data == null) return;
    _setEditingFromEvent(event, data);
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

  void _clearForm() {
    _amountCtrl.clear();
    _vendorCtrl.clear();
    _noteCtrl.clear();
    _category = null;
    _resetFormState();
  }

  void _cancelEdit() {
    _clearForm();
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
      lastDate: DateTime(now.year + 2),
      initialDate: initial,
    );
    if (picked == null) return;
    _setPickedDate(isSince, picked);
  }

  String _isoDate(DateTime input) =>
      '${input.year.toString().padLeft(4, '0')}-${input.month.toString().padLeft(2, '0')}-${input.day.toString().padLeft(2, '0')}';

  String _summary(ExpenseEventData data) =>
      '${VN.expenseTitle}: ${formatVND(data.amountVnd.toDouble())} - ${data.category} - ${data.paymentMethod}';
}
