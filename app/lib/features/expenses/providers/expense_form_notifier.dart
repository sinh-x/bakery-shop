import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/event.dart';
import '../../../data/models/event_photo.dart';
import '../../../shared/labels/expenses.dart';
import '../../../shared/labels/orders.dart';
import 'package:image_picker/image_picker.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

const _unset = Object();

class ExpenseFormDraft {
  const ExpenseFormDraft({
    this.amount = '',
    this.vendor = '',
    this.note = '',
    this.category,
    this.subcategory,
    this.paymentMethod = OrdersLabels.methodCash,
    this.paymentSource = ExpensesLabels.paymentSourceDrawerCash,
    this.paidByName,
    required this.eventDateTime,
    this.selectedPhotos = const <XFile>[],
    this.existingPhotos = const <EventPhoto>[],
  });

  final String amount;
  final String vendor;
  final String note;
  final String? category;
  final String? subcategory;
  final String paymentMethod;
  final String paymentSource;
  final String? paidByName;
  final DateTime eventDateTime;
  final List<XFile> selectedPhotos;
  final List<EventPhoto> existingPhotos;
}

/// Form state for the expense add/edit screen (DG-404 Phase 4.1 / FR2).
///
/// Holds every field previously mutated via `setState` inside
/// `_ExpenseFormScreenState`: `category`, `subcategory`, `paymentMethod`,
/// `paymentSource`, `paidByName`, `staffName`, `eventDateTime`, `loading`,
/// `editingId`, locally-picked `selectedPhotos`, and edit-mode
/// `existingPhotos`. The widget reads [expenseFormProvider] and invokes
/// the notifier's mutators; no `setState` is required.
class ExpenseFormState {
  const ExpenseFormState({
    this.editingId,
    this.category,
    this.subcategory,
    this.paymentMethod = OrdersLabels.methodCash,
    this.paymentSource = ExpensesLabels.paymentSourceDrawerCash,
    this.staffName,
    this.paidByName,
    required this.eventDateTime,
    this.loading = false,
    this.selectedPhotos = const <XFile>[],
    this.existingPhotos = const <EventPhoto>[],
    required this.newDraft,
  });

  final int? editingId;
  final String? category;
  final String? subcategory;
  final String paymentMethod;
  final String paymentSource;
  final String? staffName;
  final String? paidByName;
  final DateTime eventDateTime;
  final bool loading;
  final List<XFile> selectedPhotos;
  final List<EventPhoto> existingPhotos;
  final ExpenseFormDraft newDraft;

  bool get editing => editingId != null;

  ExpenseFormState copyWith({
    Object? editingId = _unset,
    Object? category = _unset,
    Object? subcategory = _unset,
    String? paymentMethod,
    String? paymentSource,
    String? staffName,
    Object? paidByName = _unset,
    DateTime? eventDateTime,
    bool? loading,
    List<XFile>? selectedPhotos,
    List<EventPhoto>? existingPhotos,
    ExpenseFormDraft? newDraft,
  }) {
    return ExpenseFormState(
      editingId: identical(editingId, _unset)
          ? this.editingId
          : editingId as int?,
      category: identical(category, _unset)
          ? this.category
          : category as String?,
      subcategory: identical(subcategory, _unset)
          ? this.subcategory
          : subcategory as String?,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentSource: paymentSource ?? this.paymentSource,
      staffName: staffName ?? this.staffName,
      paidByName: identical(paidByName, _unset)
          ? this.paidByName
          : paidByName as String?,
      eventDateTime: eventDateTime ?? this.eventDateTime,
      loading: loading ?? this.loading,
      selectedPhotos: selectedPhotos ?? this.selectedPhotos,
      existingPhotos: existingPhotos ?? this.existingPhotos,
      newDraft: newDraft ?? this.newDraft,
    );
  }

  ExpenseFormDraft toDraft({
    String amount = '',
    String vendor = '',
    String note = '',
  }) => ExpenseFormDraft(
    amount: amount,
    vendor: vendor,
    note: note,
    category: category,
    subcategory: subcategory,
    paymentMethod: paymentMethod,
    paymentSource: paymentSource,
    paidByName: paidByName,
    eventDateTime: eventDateTime,
    selectedPhotos: selectedPhotos,
    existingPhotos: existingPhotos,
  );
}

/// `Notifier` that owns the expense-form state (DG-404 Phase 4.1 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_ExpenseFormScreenState` are now exposed as notifier methods. The
/// widget reads the state via [expenseFormProvider] and rebuilds on
/// change — no `setState` is required.
class ExpenseFormNotifier extends Notifier<ExpenseFormState> {
  ExpenseFormNotifier([this.context]);

  final FormDraftContext? context;
  bool _initialized = false;
  bool get hasRetainedDraft =>
      context != null &&
      ref.read(formDraftSessionProvider).containsKey(context);
  ExpenseFormDraft get draftSnapshot => state.newDraft;

  bool clearAfterSuccess(ExpenseFormDraft expected, {String? staffName}) {
    if (context == null) {
      clearNewDraft(staffName: staffName);
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) {
      state = _fromDraft(
        ExpenseFormDraft(eventDateTime: DateTime.now()),
        staffName: staffName,
      );
    }
    return cleared;
  }

  @override
  ExpenseFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    final retained = context == null
        ? null
        : ref
              .read(formDraftSessionProvider.notifier)
              .readDraft<ExpenseFormDraft>(context!);
    _initialized = retained != null;
    final draft = retained ?? ExpenseFormDraft(eventDateTime: DateTime.now());
    return _fromDraft(draft);
  }

  /// Seed the initial form state from the (optional) [BakeryEvent] being
  /// edited and the logged-in staff name. Called once from the screen's
  /// `initState` before any mutation. Has no effect when [event] is `null`
  /// (add mode) — only `staffName` is applied.
  void startNew({String? staffName}) {
    if (hasRetainedDraft) return;
    state = _fromDraft(state.newDraft, staffName: staffName);
    _initialized = true;
  }

  void startEdit({required BakeryEvent event, String? staffName}) {
    if (hasRetainedDraft) return;
    state = ExpenseFormState(
      editingId: event.id,
      staffName: staffName,
      eventDateTime: event.timestamp,
      newDraft: state.newDraft,
    );
  }

  void initializeEditFields({
    required String amount,
    required String vendor,
    required String note,
    required String category,
    required String? subcategory,
    required String paymentMethod,
    required String paymentSource,
    required String? paidByName,
  }) {
    if (hasRetainedDraft) return;
    final next = state.copyWith(
      category: category,
      subcategory: subcategory,
      paymentMethod: paymentMethod,
      paymentSource: paymentSource,
      paidByName: paidByName,
    );
    state = next.copyWith(
      newDraft: next.toDraft(amount: amount, vendor: vendor, note: note),
    );
    _initialized = true;
  }

  void clearNewDraft({String? staffName}) {
    final draft = ExpenseFormDraft(eventDateTime: DateTime.now());
    state = _fromDraft(draft, staffName: staffName);
    if (context != null) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  ExpenseFormState _fromDraft(ExpenseFormDraft draft, {String? staffName}) =>
      ExpenseFormState(
        editingId: context?.mode == FormDraftMode.edit
            ? int.tryParse(context?.entityId ?? '')
            : null,
        category: draft.category,
        subcategory: draft.subcategory,
        paymentMethod: draft.paymentMethod,
        paymentSource: draft.paymentSource,
        paidByName: draft.paidByName,
        staffName: staffName,
        eventDateTime: draft.eventDateTime,
        selectedPhotos: context == null
            ? const <XFile>[]
            : draft.selectedPhotos,
        existingPhotos: context == null
            ? const <EventPhoto>[]
            : draft.existingPhotos,
        newDraft: draft,
      );

  void _update(ExpenseFormState next) {
    if (next.editing && context == null) {
      state = next;
      return;
    }
    final draft = next.toDraft(
      amount: next.newDraft.amount,
      vendor: next.newDraft.vendor,
      note: next.newDraft.note,
    );
    state = next.copyWith(newDraft: draft);
    if (context != null && _initialized) {
      ref.read(formDraftSessionProvider.notifier).retainDraft(context!, draft);
    }
  }

  void setAmount(String value) => _update(
    state.copyWith(
      newDraft: state.toDraft(
        amount: value,
        vendor: state.newDraft.vendor,
        note: state.newDraft.note,
      ),
    ),
  );

  void setVendor(String value) => _update(
    state.copyWith(
      newDraft: state.toDraft(
        amount: state.newDraft.amount,
        vendor: value,
        note: state.newDraft.note,
      ),
    ),
  );

  void setNote(String value) => _update(
    state.copyWith(
      newDraft: state.toDraft(
        amount: state.newDraft.amount,
        vendor: state.newDraft.vendor,
        note: value,
      ),
    ),
  );

  void setSubcategory(String? value) =>
      _update(state.copyWith(subcategory: value));

  void setCategory(String? value) =>
      _update(state.copyWith(category: value, subcategory: null));

  void setPaymentMethod(String value) =>
      _update(state.copyWith(paymentMethod: value));

  void setPaymentSource(String value) =>
      _update(state.copyWith(paymentSource: value));

  void setPaidByName(String? value) =>
      _update(state.copyWith(paidByName: value));

  void setLoading(bool value) => state = state.copyWith(loading: value);

  void setSelectedPhotos(List<XFile> files) =>
      _update(state.copyWith(selectedPhotos: files));

  void addExistingPhotos(List<EventPhoto> photos) => state = state.copyWith(
    existingPhotos: [...state.existingPhotos, ...photos],
  );

  /// Replace the date portion of [eventDateTime] keeping the time.
  void setDate(DateTime picked) => _update(
    state.copyWith(
      eventDateTime: DateTime(
        picked.year,
        picked.month,
        picked.day,
        state.eventDateTime.hour,
        state.eventDateTime.minute,
      ),
    ),
  );

  /// Replace the time portion of [eventDateTime] keeping the date.
  void setTime(TimeOfDay picked) => _update(
    state.copyWith(
      eventDateTime: DateTime(
        state.eventDateTime.year,
        state.eventDateTime.month,
        state.eventDateTime.day,
        picked.hour,
        picked.minute,
      ),
    ),
  );
}

/// Provider for the expense-form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final expenseFormProvider =
    NotifierProvider<ExpenseFormNotifier, ExpenseFormState>(
      ExpenseFormNotifier.new,
    );

final contextualExpenseFormProvider =
    NotifierProvider.family<
      ExpenseFormNotifier,
      ExpenseFormState,
      FormDraftContext
    >(ExpenseFormNotifier.new);
