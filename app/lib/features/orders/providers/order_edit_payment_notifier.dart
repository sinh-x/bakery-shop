import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

/// Order edit-payment sheet state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_type`, `_method`, `_paymentSource`, `_createdAt`, and
/// `_submitting` fields previously mutated via `setState` inside
/// `_OrderEditPaymentSheetState`. The widget reads [orderEditPaymentProvider]
/// and invokes the notifier's mutators; no `setState` is required.
///
/// `_createdAt` (DG-415 Phase 3 / FR2) is seeded from the existing transaction
/// so the edit sheet's picker opens pre-filled with the stored timestamp.
class OrderEditPaymentState {
  const OrderEditPaymentState({
    required this.type,
    required this.method,
    this.paymentSource,
    this.createdAt,
    this.amount = '',
    this.notes = '',
    this.isDirty = false,
  });

  final String type;
  final String method;
  final String? paymentSource;
  final DateTime? createdAt;
  final String amount;
  final String notes;
  final bool isDirty;

  OrderEditPaymentState copyWith({
    String? type,
    String? method,
    String? paymentSource,
    DateTime? createdAt,
    String? amount,
    String? notes,
    bool? isDirty,
    bool clearPaymentSource = false,
    bool clearCreatedAt = false,
  }) => OrderEditPaymentState(
    type: type ?? this.type,
    method: method ?? this.method,
    paymentSource: clearPaymentSource
        ? null
        : (paymentSource ?? this.paymentSource),
    createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
    amount: amount ?? this.amount,
    notes: notes ?? this.notes,
    isDirty: isDirty ?? this.isDirty,
  );
}

class OrderEditPaymentNotifier extends Notifier<OrderEditPaymentState> {
  OrderEditPaymentNotifier(this.context);

  final FormDraftContext context;

  @override
  OrderEditPaymentState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) =>
          state = const OrderEditPaymentState(type: 'deposit', method: 'cash'),
    );
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const OrderEditPaymentState(type: 'deposit', method: 'cash');
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<OrderEditPaymentState>(context) ??
        const OrderEditPaymentState(type: 'deposit', method: 'cash');
  }

  void _set(OrderEditPaymentState next) {
    state = next.copyWith(isDirty: true);
    ref.read(formDraftSessionProvider.notifier).retainDraft(context, state);
  }

  /// Seed the initial values from the transaction being edited. Called once
  /// from the widget's `initState` before any mutation. `createdAt` (FR2)
  /// pre-fills the date+time picker with the existing transaction timestamp.
  void seed({
    required String type,
    required String method,
    String? paymentSource,
    DateTime? createdAt,
    required String amount,
    required String notes,
  }) => ref.read(formDraftSessionProvider).containsKey(context)
      ? null
      : state = OrderEditPaymentState(
          type: type,
          method: method,
          paymentSource: paymentSource,
          createdAt: createdAt,
          amount: amount,
          notes: notes,
        );

  void setType(String type) => _set(state.copyWith(type: type));

  void setMethod(String method) => _set(
    state.copyWith(method: method, clearPaymentSource: method != 'transfer'),
  );

  void setPaymentSource(String? value) => _set(
    state.copyWith(paymentSource: value, clearPaymentSource: value == null),
  );

  void setAmount(String value) => _set(state.copyWith(amount: value));

  void setNotes(String value) => _set(state.copyWith(notes: value));

  /// FR2/FR7: replace the picker's date component while keeping the time.
  void setCreatedDate(DateTime date) {
    final current = state.createdAt ?? DateTime.now();
    _set(
      state.copyWith(
        createdAt: DateTime(
          date.year,
          date.month,
          date.day,
          current.hour,
          current.minute,
          current.second,
        ),
      ),
    );
  }

  /// FR2: replace the picker's time component while keeping the date.
  void setCreatedTime(TimeOfDay time) {
    final current = state.createdAt ?? DateTime.now();
    _set(
      state.copyWith(
        createdAt: DateTime(
          current.year,
          current.month,
          current.day,
          time.hour,
          time.minute,
        ),
      ),
    );
  }

  void clearDraft() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = const OrderEditPaymentState(type: 'deposit', method: 'cash');
  }
}

final orderEditPaymentProvider =
    NotifierProvider.family<
      OrderEditPaymentNotifier,
      OrderEditPaymentState,
      FormDraftContext
    >(OrderEditPaymentNotifier.new);
