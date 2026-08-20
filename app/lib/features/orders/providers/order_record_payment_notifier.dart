import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Order record-payment sheet state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_type`, `_method`, `_paymentSource`, `_pendingTransferPhoto`,
/// and `_submitting` fields previously mutated via `setState` inside
/// `_OrderRecordPaymentSheetState`. The widget reads
/// [orderRecordPaymentProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class OrderRecordPaymentState {
  const OrderRecordPaymentState({
    required this.type,
    required this.method,
    this.paymentSource,
    this.pendingTransferPhoto,
    this.submitting = false,
  });

  final String type;
  final String method;
  final String? paymentSource;
  final XFile? pendingTransferPhoto;
  final bool submitting;

  OrderRecordPaymentState copyWith({
    String? type,
    String? method,
    String? paymentSource,
    XFile? pendingTransferPhoto,
    bool? submitting,
    bool clearPaymentSource = false,
    bool clearPendingPhoto = false,
  }) =>
      OrderRecordPaymentState(
        type: type ?? this.type,
        method: method ?? this.method,
        paymentSource:
            clearPaymentSource ? null : (paymentSource ?? this.paymentSource),
        pendingTransferPhoto:
            clearPendingPhoto ? null : (pendingTransferPhoto ?? this.pendingTransferPhoto),
        submitting: submitting ?? this.submitting,
      );
}

class OrderRecordPaymentNotifier extends Notifier<OrderRecordPaymentState> {
  @override
  OrderRecordPaymentState build() => const OrderRecordPaymentState(
        type: 'deposit',
        method: 'cash',
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

  void setSubmitting(bool value) =>
      state = state.copyWith(submitting: value);
}

final orderRecordPaymentProvider =
    NotifierProvider<OrderRecordPaymentNotifier, OrderRecordPaymentState>(
        OrderRecordPaymentNotifier.new);