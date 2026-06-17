import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/expense_constants.dart';
import 'package:bakery_app/features/expenses/widgets/expense_form_card.dart';
import 'package:bakery_app/providers/events_provider.dart';
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
  final _staffCtrl = TextEditingController();
  bool _loading = false;
  int? _editingId;
  String? _category;
  String _paymentMethod = VN.methodCash;
  String _paymentSource = VN.paymentSourceShopCash;
  late DateTime _eventDateTime;

  bool get _editing => _editingId != null;

  @override
  void initState() {
    super.initState();
    try {
      _staffCtrl.text = ref.read(loggedByProvider);
    } catch (_) {
      _staffCtrl.text = '';
    }
    _eventDateTime = DateTime.now();
    final event = widget.event;
    if (event == null) return;
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
    _staffCtrl.text = data.staffName;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _vendorCtrl.dispose();
    _noteCtrl.dispose();
    _staffCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            staffCtrl: _staffCtrl,
            categories: expenseCategories,
            paymentMethods: expensePaymentMethods,
            paymentSources: expensePaymentSources,
            category: _category,
            paymentMethod: _paymentMethod,
            paymentSource: _paymentSource,
            eventDateTime: _eventDateTime,
            loading: _loading,
            editing: _editing,
            onCategoryChanged: (value) => setState(() => _category = value),
            onPaymentMethodChanged: (value) =>
                setState(() => _paymentMethod = value ?? _paymentMethod),
            onPaymentSourceChanged: (value) =>
                setState(() => _paymentSource = value ?? _paymentSource),
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
    if (_paymentSource == VN.paymentSourceStaffAdvance &&
        _staffCtrl.text.trim().isEmpty) {
      showTopSnackBar(context, VN.expenseStaffNameRequiredForAdvance);
      return;
    }
    final amount = int.parse(_amountCtrl.text.trim());
    // reimbursed toggle is deferred per requirements (DG-176); reimbursed defaults to false
    final payload = ExpenseEventData(
      amountVnd: amount,
      category: _category!,
      paymentMethod: _paymentMethod,
      paymentSource: _paymentSource,
      vendor: _vendorCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      staffName: _staffCtrl.text.trim(),
    );

    setState(() => _loading = true);
    try {
      if (_editing) {
        await ref
            .read(eventsProvider.notifier)
            .updateEvent(
              id: _editingId!,
              summary: _summary(payload),
              loggedBy: payload.staffName,
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
              loggedBy: payload.staffName,
              data: ExpenseEventMapper.toDataMap(payload),
              timestamp: _eventDateTime,
            );
        if (mounted) showTopSnackBar(context, VN.eventLogged);
      }
      await ref.read(loggedByProvider.notifier).setName(payload.staffName);
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
