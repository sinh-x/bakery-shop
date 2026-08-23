import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

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
    this.customerName = '',
    this.customerPhone = '',
    this.deliveryAddress = '',
    this.deliveryPhone = '',
    this.notes = '',
    this.isDirty = false,
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
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String deliveryPhone;
  final String notes;
  final bool isDirty;

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
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
    String? deliveryPhone,
    String? notes,
    bool? isDirty,
    bool clearSelectedCustomer = false,
    bool clearAssignedStaffId = false,
    bool clearDueDate = false,
    bool clearDueTime = false,
    bool clearExistingLatitude = false,
    bool clearExistingLongitude = false,
    bool clearExistingGoogleMapsUrl = false,
  }) => OrderEditWizardState(
    selectedCustomer: clearSelectedCustomer
        ? null
        : (selectedCustomer ?? this.selectedCustomer),
    customerTouched: customerTouched ?? this.customerTouched,
    deliveryType: deliveryType ?? this.deliveryType,
    shippingFee: shippingFee ?? this.shippingFee,
    dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
    currentStage: currentStage ?? this.currentStage,
    saving: saving ?? this.saving,
    source: source ?? this.source,
    assignedStaffId: clearAssignedStaffId
        ? null
        : (assignedStaffId ?? this.assignedStaffId),
    assignedStaffTouched: assignedStaffTouched ?? this.assignedStaffTouched,
    existingLatitude: clearExistingLatitude
        ? null
        : (existingLatitude ?? this.existingLatitude),
    existingLongitude: clearExistingLongitude
        ? null
        : (existingLongitude ?? this.existingLongitude),
    existingGoogleMapsUrl: clearExistingGoogleMapsUrl
        ? null
        : (existingGoogleMapsUrl ?? this.existingGoogleMapsUrl),
    deliveryPhoneDiverged: deliveryPhoneDiverged ?? this.deliveryPhoneDiverged,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    deliveryAddress: deliveryAddress ?? this.deliveryAddress,
    deliveryPhone: deliveryPhone ?? this.deliveryPhone,
    notes: notes ?? this.notes,
    isDirty: isDirty ?? this.isDirty,
  );
}

class OrderEditWizardNotifier extends Notifier<OrderEditWizardState> {
  OrderEditWizardNotifier(this.context);

  final FormDraftContext context;
  int _saveGeneration = 0;

  @override
  OrderEditWizardState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      _saveGeneration++;
      state = const OrderEditWizardState();
    });
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const OrderEditWizardState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<OrderEditWizardState>(context) ??
        const OrderEditWizardState();
  }

  void _set(OrderEditWizardState next) {
    state = next.copyWith(isDirty: true);
    ref
        .read(formDraftSessionProvider.notifier)
        .retainDraft(context, state.copyWith(saving: false));
  }

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
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    required String deliveryPhone,
    required String notes,
  }) => ref.read(formDraftSessionProvider).containsKey(context)
      ? null
      : state = OrderEditWizardState(
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
          customerName: customerName,
          customerPhone: customerPhone,
          deliveryAddress: deliveryAddress,
          deliveryPhone: deliveryPhone,
          notes: notes,
        );

  void setSelectedCustomer(Customer? customer) => _set(
    state.copyWith(
      selectedCustomer: customer,
      clearSelectedCustomer: customer == null,
      customerTouched: true,
    ),
  );

  void seedSelectedCustomer(Customer customer) {
    if (state.isDirty) return;
    state = state.copyWith(selectedCustomer: customer);
  }

  void clearSelectedCustomer() {
    if (state.selectedCustomer != null) {
      _set(state.copyWith(clearSelectedCustomer: true, customerTouched: true));
    }
  }

  void updateDeliveryTypeAndShippingFee(String type, double shippingFee) =>
      _set(state.copyWith(deliveryType: type, shippingFee: shippingFee));

  void setShippingFee(double fee) => _set(state.copyWith(shippingFee: fee));

  void setDueDate(DateTime date) => _set(state.copyWith(dueDate: date));

  void setDueTime(TimeOfDay? time) =>
      _set(state.copyWith(dueTime: time, clearDueTime: time == null));

  void goToStage(int stage) => _set(state.copyWith(currentStage: stage));

  void setSaving(bool value) => state = state.copyWith(saving: value);

  int startSaving() {
    state = state.copyWith(saving: true);
    return ++_saveGeneration;
  }

  void finishSavingIfCurrent(int generation) {
    if (generation == _saveGeneration) {
      state = state.copyWith(saving: false);
    }
  }

  void setSource(String s) => _set(state.copyWith(source: s));

  void setAssignedStaffId(String? staffId) => _set(
    state.copyWith(
      assignedStaffId: staffId,
      clearAssignedStaffId: staffId == null,
      assignedStaffTouched: true,
    ),
  );

  void setAddressSelected(String? googleMapsUrl, {bool clearCoords = true}) =>
      _set(
        state.copyWith(
          existingGoogleMapsUrl: googleMapsUrl,
          clearExistingGoogleMapsUrl: googleMapsUrl == null,
          clearExistingLatitude: clearCoords,
          clearExistingLongitude: clearCoords,
        ),
      );

  void setCustomerName(String value) =>
      _set(state.copyWith(customerName: value));
  void setCustomerPhone(String value) =>
      _set(state.copyWith(customerPhone: value));
  void setDeliveryAddress(String value) =>
      _set(state.copyWith(deliveryAddress: value));
  void setDeliveryPhone(String value) =>
      _set(state.copyWith(deliveryPhone: value));
  void setNotes(String value) => _set(state.copyWith(notes: value));

  void clearDraft() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = const OrderEditWizardState();
  }
}

final orderEditWizardProvider =
    NotifierProvider.family<
      OrderEditWizardNotifier,
      OrderEditWizardState,
      FormDraftContext
    >(OrderEditWizardNotifier.new);
