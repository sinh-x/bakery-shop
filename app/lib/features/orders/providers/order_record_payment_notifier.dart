import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

/// Order record-payment sheet state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_type`, `_method`, `_paymentSource`, `_pendingTransferPhoto`,
/// `_createdAt`, and `_submitting` fields previously mutated via `setState`
/// inside `_OrderRecordPaymentSheetState`. The widget reads
/// [orderRecordPaymentProvider] and invokes the notifier's mutators; no
/// `setState` is required.
///
/// `_createdAt` (DG-415 Phase 3 / FR1) defaults to the current local time so
/// the create sheet's date+time picker opens at "now" before staff edits it.
class OrderRecordPaymentState {
  const OrderRecordPaymentState({
    required this.type,
    required this.method,
    this.paymentSource,
    this.pendingTransferPhoto,
    this.amount = '',
    this.notes = '',
    this.createdAt,
    this.dirty = false,
  });

  final String type;
  final String method;
  final String? paymentSource;
  final XFile? pendingTransferPhoto;
  final String amount;
  final String notes;
  final DateTime? createdAt;
  final bool dirty;

  bool get isDirty =>
      dirty ||
      type != 'deposit' ||
      method != 'cash' ||
      paymentSource != null ||
      pendingTransferPhoto != null ||
      amount.isNotEmpty ||
      notes.isNotEmpty;

  OrderRecordPaymentState copyWith({
    String? type,
    String? method,
    String? paymentSource,
    XFile? pendingTransferPhoto,
    String? amount,
    String? notes,
    DateTime? createdAt,
    bool clearPaymentSource = false,
    bool clearPendingPhoto = false,
    bool clearCreatedAt = false,
    bool? dirty,
  }) => OrderRecordPaymentState(
    type: type ?? this.type,
    method: method ?? this.method,
    paymentSource: clearPaymentSource
        ? null
        : (paymentSource ?? this.paymentSource),
    pendingTransferPhoto: clearPendingPhoto
        ? null
        : (pendingTransferPhoto ?? this.pendingTransferPhoto),
    amount: amount ?? this.amount,
    notes: notes ?? this.notes,
    createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
    dirty: dirty ?? this.dirty,
  );
}

class OrderRecordPaymentNotifier extends Notifier<OrderRecordPaymentState> {
  OrderRecordPaymentNotifier(this.context);

  final FormDraftContext context;

  @override
  OrderRecordPaymentState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      state = OrderRecordPaymentState(
        type: 'deposit',
        method: 'cash',
        createdAt: DateTime.now(),
      );
    });
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = OrderRecordPaymentState(
          type: 'deposit',
          method: 'cash',
          createdAt: DateTime.now(),
        );
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<OrderRecordPaymentState>(context) ??
        OrderRecordPaymentState(
          type: 'deposit',
          method: 'cash',
          createdAt: DateTime.now(),
        );
  }

  void _set(OrderRecordPaymentState next) {
    state = next.copyWith(dirty: true);
    final drafts = ref.read(formDraftSessionProvider.notifier);
    if (state.isDirty) {
      drafts.retainDraft(context, state);
    } else {
      drafts.clearDraft(context);
    }
  }

  /// Pre-fill the amount field when `full_payment` is selected and a
  /// remaining balance exists. The amount controller write is performed by
  /// the widget (TextEditingController integration, acceptable-use); the
  /// notifier only owns the type selection.
  void setType(String type) => _set(state.copyWith(type: type));

  void setMethod(String method) => _set(
    state.copyWith(
      method: method,
      clearPaymentSource: method != 'transfer',
      clearPendingPhoto: method != 'transfer',
    ),
  );

  void setPaymentSource(String? value) => _set(
    state.copyWith(paymentSource: value, clearPaymentSource: value == null),
  );

  void setPendingTransferPhoto(XFile? photo) => _set(
    state.copyWith(
      pendingTransferPhoto: photo,
      clearPendingPhoto: photo == null,
    ),
  );

  void setAmount(String value) => _set(state.copyWith(amount: value));

  void setNotes(String value) => _set(state.copyWith(notes: value));

  void clearPendingTransferPhoto() =>
      _set(state.copyWith(clearPendingPhoto: true));

  /// Removes a completed upload from the latest retained draft without
  /// disturbing newer edits or a replacement photo.
  bool removeUploadedPendingPhoto(XFile uploadedPhoto) {
    final drafts = ref.read(formDraftSessionProvider.notifier);
    final current = drafts.readDraft<OrderRecordPaymentState>(context);
    if (current == null ||
        !identical(current.pendingTransferPhoto, uploadedPhoto)) {
      return false;
    }

    final next = current.copyWith(clearPendingPhoto: true);
    state = next;
    drafts.retainDraft(context, next);
    return true;
  }

  /// FR1/FR7: replace the picker's date component (year/month/day) while
  /// keeping the time component. Used by the create sheet's date picker.
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

  /// FR1: replace the picker's time component (hour/minute) while keeping
  /// the date component. Used by the create sheet's time picker.
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
    state = OrderRecordPaymentState(
      type: 'deposit',
      method: 'cash',
      createdAt: DateTime.now(),
    );
  }
}

final orderRecordPaymentDraftProvider =
    NotifierProvider.family<
      OrderRecordPaymentNotifier,
      OrderRecordPaymentState,
      FormDraftContext
    >(OrderRecordPaymentNotifier.new);
