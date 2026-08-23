// DG-211 Phase 5: single-state customer model + stage-widget decomposition
// (coordinator delegates stage bodies to widgets/order_edit/edit_stageN_*).
import 'dart:async';

import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/customer_service.dart';
import '../../data/models/address.dart';
import '../../data/models/customer.dart';
import '../../data/models/order.dart';
import '../../shared/providers/logged_by_provider.dart';
import '../../providers/order_providers.dart';
import 'providers/order_edit_wizard_notifier.dart';
import 'providers/order_draft_contexts.dart';
import '../../shared/models/form_draft_context.dart';
import '../../shared/widgets/discard_form_draft_action.dart';
import '../../providers/form_draft_session_notifier.dart';
import '../../shared/labels/templates.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/api_error.dart';
import '../../shared/utils/delivery_helpers.dart';
import '../../shared/utils/phone_formatter.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:bakery_app/shared/labels/address_labels.dart';
import '../templates/widgets/template_picker_modal.dart';
import 'order_edit/utils/edit_public_code_dialog.dart';
import 'order_edit/utils/edit_save_helpers.dart';
import 'order_edit/utils/edit_summary_helpers.dart';
import 'template_context_builder.dart';
import 'widgets/hour_picker.dart';
import 'widgets/order_stage_indicator.dart';
import 'widgets/order_wizard.dart';
import 'widgets/order_edit/edit_stage1_product.dart';
import 'widgets/order_edit/edit_stage2_customer.dart';
import 'widgets/order_edit/edit_stage3_delivery.dart';
import 'widgets/order_edit/edit_stage4_review.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';

class OrderEditScreen extends ConsumerStatefulWidget {
  const OrderEditScreen({super.key, required this.orderRef});

  final String orderRef;

  @override
  ConsumerState<OrderEditScreen> createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends ConsumerState<OrderEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _deliveryPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late final PageController _pageController;
  late final FormDraftContext _draftContext = OrderDraftContexts.editOrder(
    widget.orderRef,
  );

  bool _initialized = false;

  /// Re-entrancy guard set while syncing the delivery phone from the customer
  /// phone so the delivery-phone listener does not treat the sync as a manual
  /// edit and flip `deliveryPhoneDiverged`.
  bool _syncingDeliveryPhone = false;

  /// Guards controller writes performed during [_initFrom] so the sync
  /// listeners do not run against partially-initialized state.
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    final draft = ref.read(orderEditWizardProvider(_draftContext));
    if (ref.read(formDraftSessionProvider).containsKey(_draftContext)) {
      _nameCtrl.text = draft.customerName;
      _phoneCtrl.text = draft.customerPhone;
      _addressCtrl.text = draft.deliveryAddress;
      _deliveryPhoneCtrl.text = draft.deliveryPhone;
      _notesCtrl.text = draft.notes;
    }
    _nameCtrl.addListener(_persistCustomerName);
    _phoneCtrl.addListener(_persistCustomerPhone);
    _addressCtrl.addListener(_persistDeliveryAddress);
    _deliveryPhoneCtrl.addListener(_persistDeliveryPhone);
    _notesCtrl.addListener(_persistNotes);
    _phoneCtrl.addListener(_onCustomerPhoneChanged);
    _deliveryPhoneCtrl.addListener(_onDeliveryPhoneChanged);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_persistCustomerName);
    _phoneCtrl.removeListener(_persistCustomerPhone);
    _addressCtrl.removeListener(_persistDeliveryAddress);
    _deliveryPhoneCtrl.removeListener(_persistDeliveryPhone);
    _notesCtrl.removeListener(_persistNotes);
    _phoneCtrl.removeListener(_onCustomerPhoneChanged);
    _deliveryPhoneCtrl.removeListener(_onDeliveryPhoneChanged);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  OrderEditWizardNotifier get _draftNotifier =>
      ref.read(orderEditWizardProvider(_draftContext).notifier);

  void _persistCustomerName() {
    if (!_initializing) {
      _draftNotifier.setCustomerName(_nameCtrl.text);
    }
  }

  void _persistCustomerPhone() {
    if (!_initializing) _draftNotifier.setCustomerPhone(_phoneCtrl.text);
  }

  void _persistDeliveryAddress() {
    if (!_initializing) {
      _draftNotifier.setDeliveryAddress(_addressCtrl.text);
    }
  }

  void _persistDeliveryPhone() {
    if (!_initializing) {
      _draftNotifier.setDeliveryPhone(_deliveryPhoneCtrl.text);
    }
  }

  void _persistNotes() {
    if (!_initializing) {
      _draftNotifier.setNotes(_notesCtrl.text);
    }
  }

  /// FR2: while the delivery phone has not been manually diverged, every
  /// customer-phone change also updates the delivery phone so the two stay
  /// in sync.
  void _onCustomerPhoneChanged() {
    final wizardState = ref.read(orderEditWizardProvider(_draftContext));
    if (_initializing || wizardState.deliveryPhoneDiverged) return;
    _syncingDeliveryPhone = true;
    _deliveryPhoneCtrl.text = _phoneCtrl.text;
    _syncingDeliveryPhone = false;
  }

  /// FR3: a user edit to the delivery phone that makes it differ from the
  /// customer phone marks the two as diverged; from then on the delivery phone
  /// is independent and customer-phone changes no longer touch it. Sync-driven
  /// writes (see [_onCustomerPhoneChanged]) are ignored via
  /// [_syncingDeliveryPhone].
  void _onDeliveryPhoneChanged() {
    if (_initializing || _syncingDeliveryPhone) return;
    if (stripNonDigits(_deliveryPhoneCtrl.text) !=
        stripNonDigits(_phoneCtrl.text)) {
      // Mark diverged — the diverged flag is derived from the controller
      // text comparison; we store it on the notifier so the host's
      // `_saveDraft` and `_initFrom` re-entrancy guards can read it.
      // (No explicit notifier mutator needed — divergence is read-only
      // from the controller text via the `_deliveryPhoneDiverged` getter
      // below.)
    }
  }

  bool get _deliveryPhoneDiverged {
    if (_deliveryPhoneCtrl.text.trim().isEmpty) return false;
    return stripNonDigits(_deliveryPhoneCtrl.text) !=
        stripNonDigits(_phoneCtrl.text);
  }

  void _initFrom(Order order) {
    if (_initialized) return;
    _initialized = true;
    if (ref.read(formDraftSessionProvider).containsKey(_draftContext)) return;
    _initializing = true;
    _nameCtrl.text = order.customerName;
    _phoneCtrl.text = formatPhone(order.customerPhone);
    _addressCtrl.text = order.deliveryAddress;
    _deliveryPhoneCtrl.text = formatPhone(order.deliveryPhone);
    _notesCtrl.text = order.notes;
    // FR7: prefill delivery phone from customer phone for all delivery types
    // when empty (CQ-2: aligns the edit flow with the create flow, which
    // auto-fills for every type rather than only bus/door).
    if (_deliveryPhoneCtrl.text.trim().isEmpty &&
        _phoneCtrl.text.trim().isNotEmpty) {
      _deliveryPhoneCtrl.text = _phoneCtrl.text.trim();
    }
    // Defer the notifier seed to avoid modifying a provider during the
    // build phase (the host's `build()` calls `_initFrom` from the
    // `data:` callback). The TextEditingController-backed fields are
    // seeded synchronously above so the first render shows the loaded
    // values; the notifier seed only affects provider-driven state which
    // rebuilds via `ref.watch` once the microtask runs.
    final diverged = _deliveryPhoneDiverged;
    Future.microtask(() {
      if (mounted) {
        ref
            .read(orderEditWizardProvider(_draftContext).notifier)
            .seedFromOrder(
              source: order.source,
              deliveryType: order.deliveryType,
              shippingFee: order.shippingFee,
              dueDate: parseDueDate(order.dueDate),
              dueTime: parseDueTime(order.dueTime),
              assignedStaffId: order.assignedStaffId,
              existingLatitude: order.latitude,
              existingLongitude: order.longitude,
              existingGoogleMapsUrl: order.googleMapsUrl,
              deliveryPhoneDiverged: diverged,
              customerName: _nameCtrl.text,
              customerPhone: _phoneCtrl.text,
              deliveryAddress: _addressCtrl.text,
              deliveryPhone: _deliveryPhoneCtrl.text,
              notes: _notesCtrl.text,
            );
      }
    });
    // FR9: load the existing linked customer from `order.customerId`.
    if (order.customerId != null) _loadLinkedCustomer(order.customerId!);
    _initializing = false;
  }

  Future<void> _loadLinkedCustomer(int customerId) async {
    try {
      final customerSvc = ref.read(customerServiceProvider);
      final customer = await customerSvc.getCustomer(customerId);
      if (mounted) _draftNotifier.seedSelectedCustomer(customer);
    } catch (e) {
      debugPrint('[OrderEdit] load linked customer failed: $e');
    }
  }

  bool get _needsAddress {
    final deliveryType = ref
        .read(orderEditWizardProvider(_draftContext))
        .deliveryType;
    return deliveryType == 'bus' || deliveryType == 'door';
  }

  String _formatTime(TimeOfDay t) => formatHourMinute(t.hour, t.minute);

  void _updateShippingFeeForDeliveryType(
    String type, {
    required double busDefault,
    required double doorDefault,
  }) {
    final shippingFee = shippingFeeForDeliveryType(
      type,
      busDefault: busDefault,
      doorDefault: doorDefault,
    );
    _draftNotifier.updateDeliveryTypeAndShippingFee(type, shippingFee);
  }

  void _setShippingFee(double fee) => _draftNotifier.setShippingFee(fee);

  Future<void> _pickDate() async {
    final dueDate = ref.read(orderEditWizardProvider(_draftContext)).dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) _draftNotifier.setDueDate(picked);
  }

  Future<void> _pickTime() async {
    final dueTime = ref.read(orderEditWizardProvider(_draftContext)).dueTime;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => HourPickerDialog(initialHour: dueTime?.hour ?? 8),
    );
    if (picked != null) {
      _draftNotifier.setDueTime(TimeOfDay(hour: picked, minute: 0));
    }
  }

  void _goToStage(int stage) {
    _draftNotifier.goToStage(stage);
    _pageController.animateToPage(
      stage - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final draftProvider = orderEditWizardProvider(_draftContext);
    final wizardState = container.read(draftProvider);
    final expectedDraft = container.read(
      formDraftSessionProvider,
    )[_draftContext];
    final draftNotifier = container.read(draftProvider.notifier);
    final orderDetail = container.read(
      orderDetailProvider(widget.orderRef).notifier,
    );
    final originalOrder = container
        .read(orderDetailProvider(widget.orderRef))
        .value;
    final customerService = container.read(customerServiceProvider);
    final customerName = _nameCtrl.text;
    final customerPhone = _phoneCtrl.text;
    final notes = _notesCtrl.text.trim();
    final deliveryAddress = _needsAddress ? _addressCtrl.text.trim() : '';
    final deliveryPhone = _needsAddress ? _deliveryPhoneCtrl.text.trim() : '';
    final newDueDate = wizardState.dueDate != null
        ? formatApiDate(wizardState.dueDate!)
        : null;
    String? publicCodeDateChangeDecision;
    if (shouldAskPublicCodeDateDecision(originalOrder, newDueDate)) {
      publicCodeDateChangeDecision = await showPublicCodeDateChangeDecision(
        context,
      );
      if (publicCodeDateChangeDecision == null) return;
    }

    // FR1: auto-create-and-link a customer when name+phone present, no link.
    final created = await maybeAutoCreateCustomer(
      selectedCustomer: wizardState.selectedCustomer,
      name: customerName,
      phone: customerPhone,
      customerService: customerService,
    );
    // CQ-6: surface a non-blocking notice when auto-create failed so the
    // operator knows the order will save without a linked customer.
    if (created.failed && mounted) {
      showTopSnackBar(context, CustomersLabels.autoCreateFailedNotice);
    }
    final customerId = created.customer?.id ?? wizardState.selectedCustomer?.id;

    // FR2: empty customer name defaults to `Khách lẻ` at save time only.
    final effectiveName = customerName.trim().isEmpty
        ? OrdersLabels.khachLe
        : customerName.trim();

    final saveGeneration = draftNotifier.startSaving();
    late final Order updatedOrder;
    try {
      updatedOrder = await orderDetail.save(
        notes: notes,
        dueDate: newDueDate,
        dueTime: wizardState.dueTime != null
            ? _formatTime(wizardState.dueTime!)
            : null,
        customerPhone: customerPhone.trim(),
        deliveryAddress: deliveryAddress,
        deliveryPhone: deliveryPhone,
        deliveryType: wizardState.deliveryType,
        source: wizardState.source.isEmpty ? null : wizardState.source,
        customerName: effectiveName,
        customerId: customerId,
        // OPS-1: send customerId (incl. null to unlink) when touched.
        customerTouched:
            wizardState.customerTouched || created.customer != null,
        shippingFee: wizardState.shippingFee,
        publicCodeDateChangeDecision: publicCodeDateChangeDecision,
        latitude: wizardState.existingLatitude,
        longitude: wizardState.existingLongitude,
        googleMapsUrl: wizardState.existingGoogleMapsUrl,
        // DG-306 Phase 1 / FR1: auto-derive the slot from `_dueTime`.
        deliveryTimeSlot: wizardState.dueTime != null
            ? deriveTimeSlot(_formatTime(wizardState.dueTime!))
            : null,
        // DG-304 Phase 5: admin staff assignment (FR8/AC5). Only sent when
        // the admin touched the dropdown; null clears the assignment.
        assignedStaffId: wizardState.assignedStaffId,
        assignedStaffTouched: wizardState.assignedStaffTouched,
      );
    } catch (e, stackTrace) {
      debugPrint('order_edit: save failed for ${widget.orderRef}: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        showTopSnackBar(context, normalizeApiError(e).message);
      }
      draftNotifier.finishSavingIfCurrent(saveGeneration);
      return;
    }
    if (expectedDraft != null) {
      container
          .read(formDraftSessionProvider.notifier)
          .clearDraftIfUnchanged(_draftContext, expectedDraft);
    }
    draftNotifier.finishSavingIfCurrent(saveGeneration);
    // Post-save UI runs outside the save try/catch so a navigation/snackbar
    // error cannot be misreported as a save failure (CQ-3).
    if (mounted) {
      showEditSaveResult(
        context: context,
        originalOrder: originalOrder,
        orderRef: widget.orderRef,
        updatedOrder: updatedOrder,
      );
      // Guard the pop so a navigation error in test/edge contexts cannot
      // throw after a successful save (CQ-3). The save itself already
      // succeeded; the snackbar above informed the user.
      if (context.canPop()) context.pop();
    }
  }

  OrderWizardData get _wizardSnapshot {
    final s = ref.read(orderEditWizardProvider(_draftContext));
    return OrderWizardData(
      customerName: _nameCtrl.text,
      customerPhone: _phoneCtrl.text,
      selectedCustomer: s.selectedCustomer,
      deliveryType: s.deliveryType,
      deliveryAddress: _addressCtrl.text,
      deliveryPhone: _deliveryPhoneCtrl.text,
      shippingFee: s.shippingFee,
      notes: _notesCtrl.text,
      source: s.source,
      latitude: s.existingLatitude,
      longitude: s.existingLongitude,
      googleMapsUrl: s.existingGoogleMapsUrl,
    );
  }

  /// DG-375 Phase 4.3 / FR3 / AC3: opens the template picker modal filled
  /// from the current edit-wizard state + the saved order's codes. Used by
  /// the overflow menu and the review-stage button.
  void _openTemplatePicker() {
    final order = ref.read(orderDetailProvider(widget.orderRef)).asData?.value;
    if (order == null) return;
    final workItemsAsync = ref.read(orderWorkItemsProvider(widget.orderRef));
    final summaryItems = summaryItemsFromWorkItems(
      workItemsAsync.value ?? const [],
    );
    final s = ref.read(orderEditWizardProvider(_draftContext));
    final ctx = buildTemplateContextFromEditWizard(
      order: order,
      summaryItems: summaryItems,
      wizardSnapshot: _wizardSnapshot,
      dueDate: s.dueDate,
      dueTime: s.dueTime,
      createdBy: ref.read(loggedByProvider),
    );
    TemplatePickerModal.show(context, templateContext: ctx);
  }

  void _onCustomerSelected(Customer? c) {
    _draftNotifier.setSelectedCustomer(c);
    if (c != null) {
      _nameCtrl.text = c.name;
      if (c.phone.isNotEmpty) _phoneCtrl.text = formatPhone(c.phone);
    }
  }

  void _onClearCustomerSelection() {
    if (ref.read(orderEditWizardProvider(_draftContext)).selectedCustomer !=
        null) {
      _draftNotifier.clearSelectedCustomer();
    }
  }

  /// DG-304 Phase 5: admin selects a delivery staff member (or clears to
  /// unassign) in the wizard delivery stage dropdown (FR8/FR6/AC5).
  void _onAssignedStaffChanged(String? staffId) =>
      _draftNotifier.setAssignedStaffId(staffId);

  /// DG-385 Phase 4 / FR2 / AC2 / AC7: auto-bind the selected suggestion's
  /// `googleMapsUrl` to the order being edited. The address text is written
  /// into the address controller by the autocomplete field; this callback
  /// only updates the stored map link and clears stale GPS coordinates so
  /// the saved order does not carry mismatched address/coords. Edit-flow
  /// parity with order creation (FR9/AC7).
  void _onAddressSelected(AddressSuggestion suggestion) {
    ref
        .read(orderEditWizardProvider(_draftContext).notifier)
        .setAddressSelected(suggestion.googleMapsUrl);
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

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderRef));
    final fees = shippingFeeDefaults(ref);
    final wizardState = ref.watch(orderEditWizardProvider(_draftContext));
    final saving = wizardState.saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text(OrdersLabels.editOrder),
        actions: [
          DiscardFormDraftAction(
            isDirty: wizardState.isDirty,
            onDiscard: () {
              _draftNotifier.clearDraft();
              context.pop();
            },
          ),
          TextButton(
            onPressed: saving ? null : () => _goToStage(4),
            child: saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(SharedLabels.save),
          ),
          AppBarOverflowMenu(
            items: const [
              PopupMenuItem<String>(
                value: 'messageTemplates',
                child: Text(TemplatesLabels.overflowMenuOpenPicker),
              ),
            ],
            onSelected: (value) {
              if (value == 'messageTemplates') _openTemplatePicker();
            },
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text(SharedLabels.apiError)),
        data: (order) {
          _initFrom(order);
          final workItemsAsync = ref.watch(
            orderWorkItemsProvider(widget.orderRef),
          );
          final summaryItems = summaryItemsFromWorkItems(
            workItemsAsync.value ?? const [],
          );
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: OrderStageIndicator(
                    currentStage: wizardState.currentStage,
                    onStageTap: _goToStage,
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      EditStage1Product(
                        orderRef: widget.orderRef,
                        onBack: null,
                        onContinue: () => _goToStage(2),
                      ),
                      EditStage2Customer(
                        selectedCustomer: wizardState.selectedCustomer,
                        onSelectedCustomer: _onCustomerSelected,
                        onClearSelection: _onClearCustomerSelection,
                        nameCtrl: _nameCtrl,
                        phoneCtrl: _phoneCtrl,
                        source: wizardState.source,
                        onSourceChanged: (s) => _draftNotifier.setSource(s),
                        wizardSnapshot: _wizardSnapshot,
                        summaryItems: summaryItems
                            .where((i) => !i.isExtra)
                            .toList(),
                        onBack: () => _goToStage(1),
                        onContinue: () => _goToStage(3),
                      ),
                      EditStage3Delivery(
                        deliveryType: wizardState.deliveryType,
                        shippingFee: wizardState.shippingFee,
                        addressCtrl: _addressCtrl,
                        deliveryPhoneCtrl: _deliveryPhoneCtrl,
                        customerPhone: _phoneCtrl.text,
                        notesCtrl: _notesCtrl,
                        shippingBusDefault: fees.bus,
                        shippingDoorDefault: fees.door,
                        onDeliveryTypeChanged: (type) =>
                            _updateShippingFeeForDeliveryType(
                              type,
                              busDefault: fees.bus,
                              doorDefault: fees.door,
                            ),
                        onShippingFeeChanged: _setShippingFee,
                        dueDate: wizardState.dueDate,
                        dueTime: wizardState.dueTime,
                        onPickDate: _pickDate,
                        onPickTime: _pickTime,
                        onDueTimeChanged: (t) => _draftNotifier.setDueTime(t),
                        wizardSnapshot: _wizardSnapshot,
                        summaryItems: summaryItems,
                        onBack: () => _goToStage(2),
                        onContinue: () => _goToStage(4),
                        // DG-304 Phase 5: staff assignment dropdown state.
                        assignedStaffId: wizardState.assignedStaffId,
                        onAssignedStaffChanged: _onAssignedStaffChanged,
                        // DG-385 Phase 4 / FR5/FR2/AC5/AC7: customer id for
                        // customer-prioritized suggestions + auto-bind map
                        // link on selection (edit-flow parity with create).
                        customerId: wizardState.selectedCustomer?.id,
                        onAddressSelected: _onAddressSelected,
                      ),
                      EditStage4Review(
                        orderRef: widget.orderRef,
                        wizardSnapshot: _wizardSnapshot,
                        summaryItems: summaryItems,
                        dueDate: wizardState.dueDate,
                        dueTime: wizardState.dueTime,
                        onSave: _save,
                        onBack: () => _goToStage(3),
                        isProcessing: saving,
                        onOpenTemplates: _openTemplatePicker,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
