import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';

/// Order-edit screen wizard state (DG-404 Phase 4.6 / FR2).
///
/// Owns the business-logic fields previously mutated via `setState` inside
/// `_OrderEditScreenState`: `_selectedCustomer`, `_customerTouched`,
/// `_deliveryType`, `_shippingFee`, `_dueDate`, `_dueTime`, `_currentStage`,
/// `_saving`, `_source`, `_assignedStaffId`, `_assignedStaffTouched`,
/// `_existingLatitude`, `_existingLongitude`, `_existingGoogleMapsUrl`, and
/// `_deliveryPhoneDiverged`.
///
/// The TextEditingController-backed name/phone/address/delivery-phone/notes
/// fields stay on the widget (TextEditingController lifecycle is
/// acceptable-use per DG-404 guardrails). The widget reads
/// [orderEditWizardProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class OrderEditWizardState {
  const OrderEditWizardState({
    this.selectedCustomer,
    this.customerTouched = false,
    this.deliveryType = 'pickup',
    this.shippingFee = 0.0,
    this.dueDate,
    this.dueTime,
    this.currentStage = 1,
    this.saving = false,
    this.source = '',
    this.assignedStaffId,
    this.assignedStaffTouched = false,
    this.existingLatitude,
    this.existingLongitude,
    this.existingGoogleMapsUrl,
    this.deliveryPhoneDiverged = false,
  });

  final Customer? selectedCustomer;
  final bool customerTouched;
  final String deliveryType;
  final double shippingFee;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final int currentStage;
  final bool saving;
  final String source;
  final String? assignedStaffId;
  final bool assignedStaffTouched;
  final double? existingLatitude;
  final double? existingLongitude;
  final String? existingGoogleMapsUrl;
  final bool deliveryPhoneDiverged;

  OrderEditWizardState copyWith({
    Customer? selectedCustomer,
    bool? customerTouched,
    String? deliveryType,
    double? shippingFee,
    DateTime? dueDate,
    TimeOfDay? dueTime,
    int? currentStage,
    bool? saving,
    String? source,
    String? assignedStaffId,
    bool? assignedStaffTouched,
    double? existingLatitude,
    double? existingLongitude,
    String? existingGoogleMapsUrl,
    bool? deliveryPhoneDiverged,
    bool clearSelectedCustomer = false,
    bool clearAssignedStaffId = false,
    bool clearDueDate = false,
    bool clearDueTime = false,
    bool clearExistingLatitude = false,
    bool clearExistingLongitude = false,
    bool clearExistingGoogleMapsUrl = false,
  }) =>
      OrderEditWizardState(
        selectedCustomer:
            clearSelectedCustomer ? null : (selectedCustomer ?? this.selectedCustomer),
        customerTouched: customerTouched ?? this.customerTouched,
        deliveryType: deliveryType ?? this.deliveryType,
        shippingFee: shippingFee ?? this.shippingFee,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
        currentStage: currentStage ?? this.currentStage,
        saving: saving ?? this.saving,
        source: source ?? this.source,
        assignedStaffId:
            clearAssignedStaffId ? null : (assignedStaffId ?? this.assignedStaffId),
        assignedStaffTouched: assignedStaffTouched ?? this.assignedStaffTouched,
        existingLatitude:
            clearExistingLatitude ? null : (existingLatitude ?? this.existingLatitude),
        existingLongitude:
            clearExistingLongitude ? null : (existingLongitude ?? this.existingLongitude),
        existingGoogleMapsUrl: clearExistingGoogleMapsUrl
            ? null
            : (existingGoogleMapsUrl ?? this.existingGoogleMapsUrl),
        deliveryPhoneDiverged:
            deliveryPhoneDiverged ?? this.deliveryPhoneDiverged,
      );
}

class OrderEditWizardNotifier extends Notifier<OrderEditWizardState> {
  @override
  OrderEditWizardState build() => const OrderEditWizardState();

  /// Seed the initial values from the loaded order. Called once from the
  /// widget's `_initFrom` before any mutation. The TextEditingController
  /// fields (name/phone/address/delivery-phone/notes) are seeded by the
  /// widget; this seeds the business-logic fields only.
  void seedFromOrder({
    required String source,
    required String deliveryType,
    required double shippingFee,
    required DateTime? dueDate,
    required TimeOfDay? dueTime,
    required String? assignedStaffId,
    required double? existingLatitude,
    required double? existingLongitude,
    required String? existingGoogleMapsUrl,
    required bool deliveryPhoneDiverged,
  }) =>
      state = OrderEditWizardState(
        source: source,
        deliveryType: deliveryType,
        shippingFee: shippingFee,
        dueDate: dueDate,
        dueTime: dueTime,
        assignedStaffId: assignedStaffId,
        existingLatitude: existingLatitude,
        existingLongitude: existingLongitude,
        existingGoogleMapsUrl: existingGoogleMapsUrl,
        deliveryPhoneDiverged: deliveryPhoneDiverged,
      );

  void setSelectedCustomer(Customer? customer) => state = state.copyWith(
        selectedCustomer: customer,
        customerTouched: true,
      );

  void clearSelectedCustomer() {
    if (state.selectedCustomer != null) {
      state = state.copyWith(
        clearSelectedCustomer: true,
        customerTouched: true,
      );
    }
  }

  void updateDeliveryTypeAndShippingFee(String type, double shippingFee) =>
      state = state.copyWith(deliveryType: type, shippingFee: shippingFee);

  void setShippingFee(double fee) =>
      state = state.copyWith(shippingFee: fee);

  void setDueDate(DateTime date) => state = state.copyWith(dueDate: date);

  void setDueTime(TimeOfDay? time) => state = state.copyWith(dueTime: time);

  void goToStage(int stage) => state = state.copyWith(currentStage: stage);

  void setSaving(bool value) => state = state.copyWith(saving: value);

  void setSource(String s) => state = state.copyWith(source: s);

  void setAssignedStaffId(String? staffId) => state = state.copyWith(
        assignedStaffId: staffId,
        assignedStaffTouched: true,
      );

  void setAddressSelected(String? googleMapsUrl, {bool clearCoords = true}) =>
      state = state.copyWith(
        existingGoogleMapsUrl: googleMapsUrl,
        clearExistingLatitude: clearCoords,
        clearExistingLongitude: clearCoords,
      );
}

final orderEditWizardProvider =
    NotifierProvider<OrderEditWizardNotifier, OrderEditWizardState>(
        OrderEditWizardNotifier.new);