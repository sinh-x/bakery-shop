import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/address.dart';
import '../../../data/providers/config_provider.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../shared/utils/config_parsers.dart';
import 'address_autocomplete_field.dart';
import 'order_delivery_section.dart';
import 'stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/address_labels.dart';
import 'package:bakery_app/shared/labels/shared.dart';
class Stage3DeliveryOptionsScreen extends ConsumerStatefulWidget {
  const Stage3DeliveryOptionsScreen({
    super.key,
    required this.onBack,
    required this.onContinue,
    this.onFastPath,
    required this.orderStateProvider,
  });

  final VoidCallback onBack;
  final VoidCallback onContinue;
  final NotifierProvider<OrderCreateStateNotifier, OrderCreateState> orderStateProvider;

  /// DG-370 Phase 5.6-c1 (UX-5): optional POS-only "Giao ngay & Thanh toán"
  /// fast-path callback. When provided (POS checkout), a button is rendered
  /// between "Quay lại" and "Tiếp tục". Null in the normal order flow.
  final VoidCallback? onFastPath;

  @override
  ConsumerState<Stage3DeliveryOptionsScreen> createState() =>
      _Stage3DeliveryOptionsScreenState();
}

class _Stage3DeliveryOptionsScreenState
    extends ConsumerState<Stage3DeliveryOptionsScreen> {
  final _addressCtrl = TextEditingController();
  final _deliveryPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = ref.read(widget.orderStateProvider);
    _addressCtrl.text = state.wizardData.deliveryAddress;
    _deliveryPhoneCtrl.text = state.wizardData.deliveryPhone;
    _notesCtrl.text = state.wizardData.notes;
    _addressCtrl.addListener(_syncToState);
    _deliveryPhoneCtrl.addListener(_syncToState);
    _notesCtrl.addListener(_syncToState);
    // CQ-1: deferring the prefill to the next frame avoids synchronously
    // mutating the provider during widget build (initState), which broke
    // 3 tests that assert the build phase does not update wizard state.
    final initialType = state.wizardData.deliveryType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybePrefillDeliveryPhone(initialType);
    });
  }

  @override
  void dispose() {
    _addressCtrl.removeListener(_syncToState);
    _deliveryPhoneCtrl.removeListener(_syncToState);
    _notesCtrl.removeListener(_syncToState);
    _addressCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _syncToState() {
    final notifier = ref.read(widget.orderStateProvider.notifier);
    final state = ref.read(widget.orderStateProvider);
    notifier.updateWizardData(
      state.wizardData.copyWith(
        deliveryAddress: _addressCtrl.text,
        deliveryPhone: _deliveryPhoneCtrl.text,
        notes: _notesCtrl.text,
      ),
    );
  }

  /// DG-303 Phase 4 / DG-306 Phase 1: the manual `deliveryTimeSlot` dropdown
  /// was removed (DG-306 Phase 1 / FR2) — the slot is auto-derived from
  /// `dueTime`. DG-306 Phase 3 / FR7: the Google Maps URL field was removed
  /// from the create form — the URL is now managed via the Google Maps modal
  /// on the order detail screen. DG-329 Phase 7 / FR9: the manual Lat/Long
  /// text fields were removed from the wizard; stored coordinates are
  /// preserved via the Google Maps modal on the order detail screen.

  void _updateDeliveryType(String type) {
    final notifier = ref.read(widget.orderStateProvider.notifier);
    final state = ref.read(widget.orderStateProvider);
    final shippingBusDefault = firstFeeOrFallback(
      ref.read(shippingFeeBusProvider).asData?.value ?? [],
      25000,
    );
    final shippingDoorDefault = firstFeeOrFallback(
      ref.read(shippingFeeDoorProvider).asData?.value ?? [],
      20000,
    );
    final shippingFee = switch (type) {
      'bus' => shippingBusDefault,
      'door' => shippingDoorDefault,
      _ => 0.0,
    };
    notifier.updateWizardData(
      state.wizardData.copyWith(
        deliveryType: type,
        shippingFee: shippingFee,
      ),
    );
    _maybePrefillDeliveryPhone(type);
  }

  /// Prefill the delivery phone from the Stage-2 customer phone for all
  /// delivery types when the delivery phone field is still empty. Never
  /// overwrite a phone the user has already entered, and keep the prefilled
  /// value synced to state so it persists in the draft and on submission.
  void _maybePrefillDeliveryPhone(String type) {
    if (_deliveryPhoneCtrl.text.trim().isNotEmpty) return;
    final customerPhone =
        ref.read(widget.orderStateProvider).wizardData.customerPhone.trim();
    if (customerPhone.isEmpty) return;
    _deliveryPhoneCtrl.text = customerPhone;
    final notifier = ref.read(widget.orderStateProvider.notifier);
    notifier.updateWizardData(
      ref
          .read(widget.orderStateProvider)
          .wizardData
          .copyWith(deliveryPhone: customerPhone),
    );
  }

  void _setShippingFee(double fee) {
    final notifier = ref.read(widget.orderStateProvider.notifier);
    final state = ref.read(widget.orderStateProvider);
    notifier.updateWizardData(
      state.wizardData.copyWith(shippingFee: fee),
    );
  }

  /// DG-385 Phase 4 / FR2 / AC2: auto-bind the selected suggestion's
  /// `googleMapsUrl` to the order when the user picks an address from the
  /// autocomplete dropdown. The address text is written into the address
  /// controller by the field; this callback only updates the map link on
  /// the order state and surfaces a non-blocking snackbar so the operator
  /// knows the link was bound (or that the library entry has no link yet).
  ///
  /// DG-388 Phase 5.6-c5 (FB-1): bind to the top-level
  /// `OrderCreateState.googleMapsUrl` (read at submit) via
  /// `updateGpsFields`, NOT the nested `wizardData.googleMapsUrl` which
  /// was never read by the submission path and silently dropped the link.
  void _onAddressSelected(AddressSuggestion suggestion) {
    final notifier = ref.read(widget.orderStateProvider.notifier);
    notifier.updateGpsFields(
      googleMapsUrl: suggestion.googleMapsUrl,
      clearGoogleMapsUrl: suggestion.googleMapsUrl == null,
      clearLatitude: true,
      clearLongitude: true,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            suggestion.googleMapsUrl != null
                ? AddressLabels.mapsLinkBoundSnack
                : AddressLabels.mapsLinkNoLinkSnack,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _retryShippingFeeConfig(String type) {
    switch (type) {
      case 'bus':
        ref.read(shippingFeeBusProvider.notifier).refresh();
      case 'door':
        ref.read(shippingFeeDoorProvider.notifier).refresh();
    }
  }

  void _onContinue() {
    _syncToState();
    final data = ref.read(widget.orderStateProvider).wizardData;
    if (data.needsAddress && data.deliveryAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(OrdersLabels.validationDeliveryAddressRequired),
        ),
      );
      return;
    }
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.orderStateProvider);
    final data = state.wizardData;

    final AsyncValue<List<String>>? feeConfig = switch (data.deliveryType) {
      'bus' => ref.watch(shippingFeeBusProvider),
      'door' => ref.watch(shippingFeeDoorProvider),
      _ => null,
    };

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: OrderDeliverySection(
              mode: OrderDeliverySectionMode.editable,
              useResponsiveLayout: true,
              deliveryType: data.deliveryType,
              shippingFee: data.shippingFee,
              addressCtrl: _addressCtrl,
              phoneCtrl: _deliveryPhoneCtrl,
              notesCtrl: data.needsNotes ? _notesCtrl : null,
              onDeliveryTypeChanged: _updateDeliveryType,
              onShippingFeeChanged: _setShippingFee,
              // DG-385 Phase 4 / FR1/FR2/FR5: autocomplete address field with
              // library suggestions, customer-prioritized ordering, and
              // auto-bind of `googleMapsUrl` on selection (AC1/AC2/AC5).
              addressField: AddressAutocompleteField(
                controller: _addressCtrl,
                customerId: data.selectedCustomer?.id,
                onSelected: _onAddressSelected,
                validator: (v) => data.needsAddress && (v == null || v.trim().isEmpty)
                    ? SharedLabels.fieldRequired
                    : null,
              ),
              dueDate: state.dueDate,
              dueTime: state.dueTime,
              onDueDateChanged: (d) => ref
                  .read(widget.orderStateProvider.notifier)
                  .updateDueDate(d),
              onDueTimeChanged: (t) => ref
                  .read(widget.orderStateProvider.notifier)
                  .updateDueTime(t),
              shippingFeeConfigLoading: feeConfig?.isLoading ?? false,
              shippingFeeConfigError:
                  (feeConfig?.hasError ?? false) ? SharedLabels.errorLoading : null,
              onRetryShippingFeeConfig: () =>
                  _retryShippingFeeConfig(data.deliveryType),
              summaryCardSlots: [
                ProductSummaryCard(items: state.items),
                CustomerSummaryCard(
                  wizardData: state.wizardData,
                  source: state.source,
                ),
                DeliverySummaryCard(
                  wizardData: state.wizardData,
                  dueDate: state.dueDate,
                  dueTime: state.dueTime,
                ),
              ],
            ),
          ),
        ),
        _buildNavigation(),
      ],
    );
  }

  Widget _buildNavigation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: widget.onBack,
            child: const Text(OrdersLabels.backLabel),
          ),
          const Spacer(),
          // DG-370 Phase 5.6-c1 (UX-5): "Giao ngay & Thanh toán" fast-path
          // button between "Quay lại" and "Tiếp tục" — POS-only.
          if (widget.onFastPath != null) ...[
            FilledButton.icon(
              onPressed: widget.onFastPath,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text(OrdersLabels.posGiaoNgayThanhToan),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton(
            onPressed: _onContinue,
            child: const Text(OrdersLabels.continueLabel),
          ),
        ],
      ),
    );
  }
}
