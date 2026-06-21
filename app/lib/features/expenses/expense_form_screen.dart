import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/expense_constants.dart';
import 'package:bakery_app/features/expenses/widgets/expense_form_card.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/providers/staff_provider.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key, this.event});

  final BakeryEvent? event;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _loading = false;
  int? _editingId;
  String? _category;
  String _paymentMethod = VN.methodCash;
  String _paymentSource = VN.paymentSourceShopCash;
  String? _staffName;
  String? _paidByName;
  late DateTime _eventDateTime;

  bool get _editing => _editingId != null;

  @override
  void initState() {
    super.initState();
    _eventDateTime = DateTime.now();
    final event = widget.event;
    if (event == null) {
      _staffName = ref.read(loggedByProvider);
      return;
    }
    _editingId = event.id;
    _eventDateTime = event.timestamp.toLocal();
    final data = ExpenseEventMapper.fromEvent(event);
    if (data == null) return;
    _amountCtrl.text = data.amountVnd.toString();
    _category = data.category;
    _paymentMethod = data.paymentMethod;
    _paymentSource = data.paymentSource;
    _vendorCtrl.text = data.vendor;
    _noteCtrl.text = data.note;
    _staffName = data.loggedBy.isNotEmpty ? data.loggedBy : null;
    _paidByName = data.paidByName.isNotEmpty ? data.paidByName : null;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _vendorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    final staffList = staffAsync.whenOrNull<List<String>>(
          data: (members) =>
              members.where((m) => m.active).map((m) => m.name).toList(),
        ) ??
        const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? VN.expenseUpdateAction : VN.expenseAddAction),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ExpenseFormCard(
            formKey: _formKey,
            amountCtrl: _amountCtrl,
            vendorCtrl: _vendorCtrl,
            noteCtrl: _noteCtrl,
            categories: expenseCategories,
            paymentMethods: expensePaymentMethods,
            paymentSources: expensePaymentSources,
            staffList: staffList,
            category: _category,
            paymentMethod: _paymentMethod,
            paymentSource: _paymentSource,
            selectedPaidByName: _paidByName,
            eventDateTime: _eventDateTime,
            loading: _loading,
            editing: _editing,
            onCategoryChanged: (value) => setState(() => _category = value),
            onPaymentMethodChanged: (value) =>
                setState(() => _paymentMethod = value ?? _paymentMethod),
            onPaymentSourceChanged: (value) =>
                setState(() => _paymentSource = value ?? _paymentSource),
            onPaidByNameChanged: (value) =>
                setState(() => _paidByName = value),
            onPickDate: _pickDate,
            onPickTime: _pickTime,
            onCancelEdit: () => context.pop(false),
            onSave: _save,
            amountValidator: _validateAmount,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null || _category!.isEmpty) return;

    final loggedBy = ref.read(loggedByProvider);
    if (loggedBy.isEmpty) {
      showTopSnackBar(context, VN.expenseEmptyStaffWarning);
      return;
    }

    if (_paidByName == null || _paidByName!.isEmpty) {
      final resolved = await _showPayerConfirmDialog();
      if (resolved == null) return;
      setState(() => _paidByName = resolved);
    }

    if (!mounted) return;
    if (_paymentSource == VN.paymentSourceStaffAdvance &&
        (_paidByName == null || _paidByName!.isEmpty)) {
      showTopSnackBar(context, VN.expenseStaffNameRequiredForAdvance);
      return;
    }

    final amount = int.parse(_amountCtrl.text.trim());
    final payload = ExpenseEventData(
      amountVnd: amount,
      category: _category!,
      paymentMethod: _paymentMethod,
      paymentSource: _paymentSource,
      vendor: _vendorCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      loggedBy: loggedBy,
      paidByName: _paidByName!,
    );

    setState(() => _loading = true);
    try {
      if (_editing) {
        await ref
            .read(eventsProvider.notifier)
            .updateEvent(
              id: _editingId!,
              summary: _summary(payload),
              loggedBy: loggedBy,
              data: ExpenseEventMapper.toDataMap(payload),
              timestamp: _eventDateTime,
            );
        if (mounted) showTopSnackBar(context, VN.eventUpdated);
      } else {
        await ref
            .read(eventsProvider.notifier)
            .logEvent(
              summary: _summary(payload),
              type: expenseType,
              loggedBy: loggedBy,
              data: ExpenseEventMapper.toDataMap(payload),
              timestamp: _eventDateTime,
            );
        if (mounted) showTopSnackBar(context, VN.eventLogged);
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          e is DioException ? (e.message ?? VN.apiError) : VN.apiError,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _showPayerConfirmDialog() async {
    final staffName = _staffName;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.expensePayerConfirmTitle),
        content: Text(staffName != null && staffName.isNotEmpty
            ? '${VN.expensePayerConfirmPrompt}\n\n${VN.loggedBy}: $staffName'
            : VN.expensePayerConfirmPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text(VN.cancel),
          ),
          TextButton(
            onPressed: () async {
              final custom = await _showCustomPayerDialog(ctx);
              if (ctx.mounted) {
                Navigator.of(ctx).pop(custom);
              }
            },
            child: const Text(VN.expensePayerEnterCustom),
          ),
          if (staffName != null && staffName.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(staffName),
              child: Text(
                '${VN.expensePayerUseStaff}: $staffName',
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _showCustomPayerDialog(BuildContext ctx) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(VN.expensePayerEnterCustom),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: VN.expensePayerCustomHint,
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? VN.fieldRequired : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(null),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogCtx).pop(ctrl.text.trim());
              }
            },
            child: const Text(VN.save),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  String? _validateAmount(String? value) {
    final raw = (value ?? '').trim();
    final parsed = int.tryParse(raw);
    if (raw.isEmpty || parsed == null || parsed <= 0) {
      return VN.expenseAmountValidationMessage;
    }
    return null;
  }

  String _summary(ExpenseEventData data) =>
      '${VN.expenseTitle}: ${formatVND(data.amountVnd.toDouble())} - ${data.category} - ${data.paymentMethod}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _eventDateTime,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _eventDateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _eventDateTime.hour,
        _eventDateTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eventDateTime),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _eventDateTime = DateTime(
        _eventDateTime.year,
        _eventDateTime.month,
        _eventDateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }
}
