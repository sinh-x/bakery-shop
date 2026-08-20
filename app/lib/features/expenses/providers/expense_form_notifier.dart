import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/event.dart';
import '../../../data/models/event_photo.dart';
import '../../../shared/labels/expenses.dart';
import '../../../shared/labels/orders.dart';
import 'package:image_picker/image_picker.dart';

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

  bool get editing => editingId != null;

  ExpenseFormState copyWith({
    int? editingId,
    String? category,
    String? subcategory,
    String? paymentMethod,
    String? paymentSource,
    String? staffName,
    String? paidByName,
    DateTime? eventDateTime,
    bool? loading,
    List<XFile>? selectedPhotos,
    List<EventPhoto>? existingPhotos,
  }) {
    return ExpenseFormState(
      editingId: editingId ?? this.editingId,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentSource: paymentSource ?? this.paymentSource,
      staffName: staffName ?? this.staffName,
      paidByName: paidByName ?? this.paidByName,
      eventDateTime: eventDateTime ?? this.eventDateTime,
      loading: loading ?? this.loading,
      selectedPhotos: selectedPhotos ?? this.selectedPhotos,
      existingPhotos: existingPhotos ?? this.existingPhotos,
    );
  }
}

/// `Notifier` that owns the expense-form state (DG-404 Phase 4.1 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_ExpenseFormScreenState` are now exposed as notifier methods. The
/// widget reads the state via [expenseFormProvider] and rebuilds on
/// change — no `setState` is required.
class ExpenseFormNotifier extends Notifier<ExpenseFormState> {
  @override
  ExpenseFormState build() => ExpenseFormState(
        eventDateTime: DateTime.now(),
      );

  /// Seed the initial form state from the (optional) [BakeryEvent] being
  /// edited and the logged-in staff name. Called once from the screen's
  /// `initState` before any mutation. Has no effect when [event] is `null`
  /// (add mode) — only `staffName` is applied.
  void seed({BakeryEvent? event, String? staffName}) {
    if (event == null) {
      state = state.copyWith(staffName: staffName);
      return;
    }
    state = state.copyWith(
      editingId: event.id,
      staffName: staffName,
    );
  }

  void setSubcategory(String? value) =>
      state = state.copyWith(subcategory: value);

  void setCategory(String? value) =>
      state = state.copyWith(category: value, subcategory: null);

  void setPaymentMethod(String value) =>
      state = state.copyWith(paymentMethod: value);

  void setPaymentSource(String value) =>
      state = state.copyWith(paymentSource: value);

  void setPaidByName(String? value) =>
      state = state.copyWith(paidByName: value);

  void setLoading(bool value) => state = state.copyWith(loading: value);

  void setSelectedPhotos(List<XFile> files) =>
      state = state.copyWith(selectedPhotos: files);

  void addExistingPhotos(List<EventPhoto> photos) => state = state.copyWith(
        existingPhotos: [...state.existingPhotos, ...photos],
      );

  /// Replace the date portion of [eventDateTime] keeping the time.
  void setDate(DateTime picked) => state = state.copyWith(
        eventDateTime: DateTime(
          picked.year,
          picked.month,
          picked.day,
          state.eventDateTime.hour,
          state.eventDateTime.minute,
        ),
      );

  /// Replace the time portion of [eventDateTime] keeping the date.
  void setTime(TimeOfDay picked) => state = state.copyWith(
        eventDateTime: DateTime(
          state.eventDateTime.year,
          state.eventDateTime.month,
          state.eventDateTime.day,
          picked.hour,
          picked.minute,
        ),
      );
}

/// Provider for the expense-form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final expenseFormProvider =
    NotifierProvider<ExpenseFormNotifier, ExpenseFormState>(
  ExpenseFormNotifier.new,
);