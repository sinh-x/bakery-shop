import 'package:bakery_app/shared/utils.dart' show formatVND, showTopSnackBar;
import 'package:bakery_app/data/api/api_client.dart' show apiBaseUrlProvider;
import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/data/models/expense_category.dart';
import 'package:bakery_app/features/events/widgets/event_form_photo_section.dart';
import 'package:bakery_app/features/expenses/expense_constants.dart';
import 'package:bakery_app/features/expenses/providers/expense_form_notifier.dart';
import 'package:bakery_app/features/expenses/widgets/expense_form_card.dart';
import 'package:bakery_app/data/providers/events_provider.dart';
import 'package:bakery_app/providers/photo_upload_provider.dart';
import 'package:bakery_app/data/providers/staff_provider.dart';
import 'package:bakery_app/shared/providers/logged_by_provider.dart';
import 'package:bakery_app/shared/widgets/upload_progress_indicator.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// EXEMPT: 300-line screen threshold exceeded because photo upload lifecycle
// (state, load-existing, post-submit upload) must live in the screen to keep
// ExpenseFormCard under its widget limit. Pre-existing at 352 lines before
// DG-326 Phase 3. Reviewed 2026-08-01.

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

  @override
  void initState() {
    super.initState();
    // Clear any stale upload state from a previous screen navigation
    // (DG-333 Phase 5.6-c1-fix m2) so progress/errors don't leak across
    // screens that share the global photoUploadNotifierProvider. Deferred
    // to a microtask because Riverpod disallows provider mutation during
    // widget life-cycle hooks (initState/build).
    Future.microtask(
      () => ref.read(photoUploadNotifierProvider.notifier).reset(),
    );
    final event = widget.event;
    final staffName = ref.read(loggedByProvider);
    // Defer provider mutations to a microtask because Riverpod disallows
    // provider mutation during widget life-cycle hooks (initState/build).
    Future.microtask(() {
      if (!mounted) return;
      final notifier = ref.read(expenseFormProvider.notifier);
      if (event == null) {
        notifier.seed(staffName: staffName);
        return;
      }
      notifier.seed(event: event, staffName: staffName);
      final data = ExpenseEventMapper.fromEvent(event);
      if (data == null) return;
      _amountCtrl.text = data.amountVnd.toString();
      notifier
        ..setCategory(data.category)
        ..setSubcategory(data.subcategory.isNotEmpty ? data.subcategory : null)
        ..setPaymentMethod(data.paymentMethod)
        ..setPaymentSource(data.paymentSource);
      _vendorCtrl.text = data.vendor;
      _noteCtrl.text = data.note;
      notifier.setPaidByName(data.paidByName.isNotEmpty ? data.paidByName : null);
    });
    if (event != null) {
      _loadExistingPhotos(event.id);
    }
  }

  Future<void> _loadExistingPhotos(int eventId) async {
    try {
      final service = ref.read(eventServiceProvider);
      final photos = await service.getEventPhotos(eventId);
      if (mounted) ref.read(expenseFormProvider.notifier).addExistingPhotos(photos);
    } catch (e) {
      debugPrint('_loadExistingPhotos failed: $e');
      // Non-fatal: edit form still works without existing photo display.
    }
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
    final form = ref.watch(expenseFormProvider);
    final notifier = ref.read(expenseFormProvider.notifier);
    final staffAsync = ref.watch(staffListProvider);
    final staffList = staffAsync.whenOrNull<List<String>>(
          data: (members) =>
              members.where((m) => m.active).map((m) => m.name).toList(),
        ) ??
        const <String>[];
    final vendorSuggestionsAsync = ref.watch(expenseVendorSuggestionsProvider);
    final vendorSuggestions = vendorSuggestionsAsync.whenOrNull<List<String>>(
          data: (names) => names,
        ) ??
        const <String>[];
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final categoryTree = categoriesAsync.whenOrNull<List<ExpenseCategory>>(
          data: (tree) => tree,
        ) ??
        const <ExpenseCategory>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(form.editing ? ExpensesLabels.expenseUpdateAction : ExpensesLabels.expenseAddAction),
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
            vendorSuggestions: vendorSuggestions,
            category: form.category,
            paymentMethod: form.paymentMethod,
            paymentSource: form.paymentSource,
            selectedPaidByName: form.paidByName,
            eventDateTime: form.eventDateTime,
            loading: form.loading,
            editing: form.editing,
            categoryTree: categoryTree,
            subcategory: form.subcategory,
            onSubcategoryChanged: notifier.setSubcategory,
            onCategoryChanged: notifier.setCategory,
            onPaymentMethodChanged: (value) =>
                notifier.setPaymentMethod(value ?? form.paymentMethod),
            onPaymentSourceChanged: (value) =>
                notifier.setPaymentSource(value ?? form.paymentSource),
            onPaidByNameChanged: notifier.setPaidByName,
            onPickDate: _pickDate,
            onPickTime: _pickTime,
            onCancelEdit: () => context.pop(false),
            onSave: _save,
            amountValidator: _validateAmount,
          ),
          const SizedBox(height: 8),
          EventFormPhotoSection(
            existingPhotos: form.existingPhotos,
            selectedPhotos: form.selectedPhotos,
            baseUrl: ref.read(apiBaseUrlProvider),
            onSelectionChanged: notifier.setSelectedPhotos,
          ),
          UploadProgressIndicator(
            states: ref.watch(photoUploadNotifierProvider).states,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final form = ref.read(expenseFormProvider);
    final notifier = ref.read(expenseFormProvider.notifier);
    if (form.category == null || form.category!.isEmpty) return;

    final loggedBy = ref.read(loggedByProvider);
    if (loggedBy.isEmpty) {
      showTopSnackBar(context, ExpensesLabels.expenseEmptyStaffWarning);
      return;
    }

    final isDebt = form.paymentMethod == OrdersLabels.methodDebt;

    // Debt expenses have no payment source (FR2); default the payer to the
    // logged-in staff without prompting, and skip the staff-advance check.
    String paidByName;
    if (isDebt) {
      paidByName = form.paidByName ?? loggedBy;
    } else {
      if (form.paidByName == null || form.paidByName!.isEmpty) {
        final resolved = await _showPayerConfirmDialog();
        if (resolved == null) return;
        paidByName = resolved;
        notifier.setPaidByName(resolved);
      } else {
        paidByName = form.paidByName!;
      }

      if (!mounted) return;
      if (form.paymentSource == ExpensesLabels.paymentSourceStaffAdvance &&
          paidByName.isEmpty) {
        showTopSnackBar(context, ExpensesLabels.expenseStaffNameRequiredForAdvance);
        return;
      }
    }

    if (!mounted) return;
    final amount = int.parse(_amountCtrl.text.trim());
    final payload = ExpenseEventData(
      amountVnd: amount,
      category: form.category!,
      paymentMethod: form.paymentMethod,
      paymentSource: isDebt ? '' : form.paymentSource,
      vendor: _vendorCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      loggedBy: loggedBy,
      paidByName: paidByName,
      subcategory: form.subcategory ?? '',
    );

    notifier.setLoading(true);
    try {
      final hasNewPhotos = form.selectedPhotos.isNotEmpty;
      final upload = ref.read(photoUploadNotifierProvider.notifier);
      if (form.editing) {
        await ref
            .read(eventsProvider.notifier)
            .updateEvent(
              id: form.editingId!,
              summary: _summary(payload),
              loggedBy: loggedBy,
              data: ExpenseEventMapper.toDataMap(payload),
              timestamp: form.eventDateTime,
            );
        if (hasNewPhotos && mounted) {
          await _uploadPhotos(form.editingId!, upload);
        }
        if (mounted) showTopSnackBar(context, EventsLabels.eventUpdated);
      } else {
        final createdEvent = await ref
            .read(eventsProvider.notifier)
            .logEvent(
              summary: _summary(payload),
              type: expenseType,
              loggedBy: loggedBy,
              data: ExpenseEventMapper.toDataMap(payload),
              timestamp: form.eventDateTime,
            );
        if (hasNewPhotos && mounted) {
          await _uploadPhotos(createdEvent.id, upload);
        }
        if (mounted) showTopSnackBar(context, EventsLabels.eventLogged);
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          e is DioException ? (e.message ?? SharedLabels.apiError) : SharedLabels.apiError,
        );
      }
    } finally {
      if (mounted) {
        notifier.setLoading(false);
      }
    }
  }

  /// Upload locally-picked photos to [eventId] via the shared
  /// [PhotoUploadNotifier] (FR4) so per-photo progress and error states are
  /// surfaced through the [UploadProgressIndicator] (FR1/FR2). Awaited by
  /// [_save] before `context.pop(true)` so the screen does not dismiss until
  /// every upload reaches a terminal state (FR3 — race condition fix).
  /// Remaining photos continue after a failure; a snack bar is shown only when
  /// any photo errored.
  Future<void> _uploadPhotos(
    int eventId,
    PhotoUploadNotifier upload,
  ) async {
    final service = ref.read(eventServiceProvider);
    final selected = ref.read(expenseFormProvider).selectedPhotos;
    await upload.uploadAll(
      selected,
      (file) => service.uploadEventPhoto(eventId, file),
    );
    if (mounted && ref.read(photoUploadNotifierProvider).hasErrors) {
      showTopSnackBar(context, EventsLabels.eventPhotosUploadFailed);
    }
  }

  Future<String?> _showPayerConfirmDialog() async {
    final staffName = ref.read(expenseFormProvider).staffName;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(ExpensesLabels.expensePayerConfirmTitle),
        content: Text(staffName != null && staffName.isNotEmpty
            ? '${ExpensesLabels.expensePayerConfirmPrompt}\n\n$staffName'
            : ExpensesLabels.expensePayerConfirmPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text(SharedLabels.cancel),
          ),
          TextButton(
            onPressed: () async {
              final custom = await _showCustomPayerDialog(ctx);
              if (ctx.mounted) {
                Navigator.of(ctx).pop(custom);
              }
            },
            child: const Text(ExpensesLabels.expensePayerEnterCustom),
          ),
          if (staffName != null && staffName.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(staffName),
              child: Text(
                '${ExpensesLabels.expensePayerUseStaff}: $staffName',
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
        title: const Text(ExpensesLabels.expensePayerEnterCustom),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: ExpensesLabels.expensePayerCustomHint,
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? SharedLabels.fieldRequired : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(null),
            child: const Text(SharedLabels.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogCtx).pop(ctrl.text.trim());
              }
            },
            child: const Text(SharedLabels.save),
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
      return ExpensesLabels.expenseAmountValidationMessage;
    }
    return null;
  }

  String _summary(ExpenseEventData data) {
    final tail = data.paymentMethod == OrdersLabels.methodDebt && data.vendor.isNotEmpty
        ? '${data.paymentMethod} • ${data.vendor}'
        : data.paymentMethod;
    return '${ExpensesLabels.expenseTitle}: ${formatVND(data.amountVnd.toDouble())} - ${data.category} - $tail';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: ref.read(expenseFormProvider).eventDateTime,
    );
    if (picked == null || !mounted) return;
    ref.read(expenseFormProvider.notifier).setDate(picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(ref.read(expenseFormProvider).eventDateTime),
    );
    if (picked == null || !mounted) return;
    ref.read(expenseFormProvider.notifier).setTime(picked);
  }
}