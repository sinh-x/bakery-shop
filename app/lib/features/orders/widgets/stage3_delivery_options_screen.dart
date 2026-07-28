import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/config_provider.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../shared/utils/config_parsers.dart';
import 'order_delivery_section.dart';
import 'stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class Stage3DeliveryOptionsScreen extends ConsumerStatefulWidget {
  const Stage3DeliveryOptionsScreen({
    super.key,
    required this.onBack,
    required this.onContinue,
    required this.orderStateProvider,
  });

  final VoidCallback onBack;
  final VoidCallback onContinue;
  final NotifierProvider<OrderCreateStateNotifier, OrderCreateState> orderStateProvider;

  @override
  ConsumerState<Stage3DeliveryOptionsScreen> createState() =>
      _Stage3DeliveryOptionsScreenState();
}

class _Stage3DeliveryOptionsScreenState
    extends ConsumerState<Stage3DeliveryOptionsScreen> {
  final _addressCtrl = TextEditingController();
  final _deliveryPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _latitudeCtrl = TextEditingController();
  final _longitudeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final state = ref.read(widget.orderStateProvider);
    _addressCtrl.text = state.wizardData.deliveryAddress;
    _deliveryPhoneCtrl.text = state.wizardData.deliveryPhone;
    _notesCtrl.text = state.wizardData.notes;
    _latitudeCtrl.text = state.latitude?.toString() ?? '';
    _longitudeCtrl.text = state.longitude?.toString() ?? '';
    _addressCtrl.addListener(_syncToState);
    _deliveryPhoneCtrl.addListener(_syncToState);
    _notesCtrl.addListener(_syncToState);
    _latitudeCtrl.addListener(_syncGpsToState);
    _longitudeCtrl.addListener(_syncGpsToState);
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
    _latitudeCtrl.removeListener(_syncGpsToState);
    _longitudeCtrl.removeListener(_syncGpsToState);
    _addressCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _latitudeCtrl.dispose();
    _longitudeCtrl.dispose();
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

  /// DG-303 Phase 4 / DG-306 Phase 1: sync GPS coordinate text fields back to
  /// `OrderCreateState`. Latitude/longitude are parsed to `double?` so the
  /// backend receives numeric values; invalid input is left as `null` and
  /// the field validator surfaces the error to the user. The manual
  /// `deliveryTimeSlot` dropdown was removed (DG-306 Phase 1 / FR2) — the
  /// slot is auto-derived from `dueTime`. DG-306 Phase 3 / FR7: the Google
  /// Maps URL field was removed from the create form — the URL is now
  /// managed via the Google Maps modal on the order detail screen.
  void _syncGpsToState() {
    final notifier = ref.read(widget.orderStateProvider.notifier);
    notifier.updateGpsFields(
      latitude: double.tryParse(_latitudeCtrl.text.trim()),
      longitude: double.tryParse(_longitudeCtrl.text.trim()),
    );
  }

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
                  (feeConfig?.hasError ?? false) ? VN.errorLoading : null,
              onRetryShippingFeeConfig: () =>
                  _retryShippingFeeConfig(data.deliveryType),
              latitudeCtrl: _latitudeCtrl,
              longitudeCtrl: _longitudeCtrl,
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
          FilledButton(
            onPressed: _onContinue,
            child: const Text(OrdersLabels.continueLabel),
          ),
        ],
      ),
    );
  }
}
