import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

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
    this.createdAt,
    this.submitting = false,
  });

  final String type;
  final String method;
  final String? paymentSource;
  final XFile? pendingTransferPhoto;
  final DateTime? createdAt;
  final bool submitting;

  OrderRecordPaymentState copyWith({
    String? type,
    String? method,
    String? paymentSource,
    XFile? pendingTransferPhoto,
    DateTime? createdAt,
    bool? submitting,
    bool clearPaymentSource = false,
    bool clearPendingPhoto = false,
    bool clearCreatedAt = false,
  }) =>
      OrderRecordPaymentState(
        type: type ?? this.type,
        method: method ?? this.method,
        paymentSource:
            clearPaymentSource ? null : (paymentSource ?? this.paymentSource),
        pendingTransferPhoto:
            clearPendingPhoto ? null : (pendingTransferPhoto ?? this.pendingTransferPhoto),
        createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
        submitting: submitting ?? this.submitting,
      );
}

class OrderRecordPaymentNotifier extends Notifier<OrderRecordPaymentState> {
  @override
  OrderRecordPaymentState build() => OrderRecordPaymentState(
        type: 'deposit',
        method: 'cash',
        // FR1: picker defaults to the current local time on create.
        createdAt: DateTime.now(),
      );

  /// Pre-fill the amount field when `full_payment` is selected and a
  /// remaining balance exists. The amount controller write is performed by
  /// the widget (TextEditingController integration, acceptable-use); the
  /// notifier only owns the type selection.
  void setType(String type) => state = state.copyWith(type: type);

  void setMethod(String method) => state = state.copyWith(
        method: method,
        clearPaymentSource: method != 'transfer',
        clearPendingPhoto: method != 'transfer',
      );

  void setPaymentSource(String? value) =>
      state = state.copyWith(paymentSource: value);

  void setPendingTransferPhoto(XFile? photo) =>
      state = state.copyWith(pendingTransferPhoto: photo);

  void clearPendingTransferPhoto() =>
      state = state.copyWith(clearPendingPhoto: true);

  /// FR1/FR7: replace the picker's date component (year/month/day) while
  /// keeping the time component. Used by the create sheet's date picker.
  void setCreatedDate(DateTime date) {
    final current = state.createdAt ?? DateTime.now();
    state = state.copyWith(
      createdAt: DateTime(
        date.year,
        date.month,
        date.day,
        current.hour,
        current.minute,
        current.second,
      ),
    );
  }

  /// FR1: replace the picker's time component (hour/minute) while keeping
  /// the date component. Used by the create sheet's time picker.
  void setCreatedTime(TimeOfDay time) {
    final current = state.createdAt ?? DateTime.now();
    state = state.copyWith(
      createdAt: DateTime(
        current.year,
        current.month,
        current.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void setSubmitting(bool value) =>
      state = state.copyWith(submitting: value);
}

final orderRecordPaymentProvider =
    NotifierProvider<OrderRecordPaymentNotifier, OrderRecordPaymentState>(
        OrderRecordPaymentNotifier.new);