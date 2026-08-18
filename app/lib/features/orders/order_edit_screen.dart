// DG-211 Phase 5: single-state customer model + stage-widget decomposition
// (coordinator delegates stage bodies to widgets/order_edit/edit_stageN_*).
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

  String _source = '';
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _deliveryType = 'pickup';
  double _shippingFee = 0.0;
  bool _saving = false;
  bool _initialized = false;
  // DG-303 Phase 4 / DG-306 Phase 1: GPS fields (door delivery only). The
  // manual `deliveryTimeSlot` state was removed (DG-306 Phase 1 / FR2) — the
  // slot is auto-derived from `_dueTime` at submit time via `deriveTimeSlot`.
  // DG-306 Phase 3 / FR7: the Google Maps URL field was removed from the
  // edit form — the URL is now managed via the Google Maps modal on the
  // order detail screen. The existing URL is preserved at save time by
  // passing the loaded order's `googleMapsUrl` back to the backend.
  // DG-329 Phase 7 / FR9: the manual Lat/Long text fields were removed from
  // the edit wizard. The loaded order's stored coordinates are preserved
  // verbatim at save time (no user editing in the wizard); coordinates are
  // managed via the Google Maps modal on the order detail screen.
  double? _existingLatitude;
  double? _existingLongitude;
  String? _existingGoogleMapsUrl;
  // FR9: single-state customer model (was tri-state: _selectedCustomer +
  // _linkedCustomerId + _customerTouched). The existing linked customer is
  // loaded from `order.customerId` into `_selectedCustomer` on open.
  Customer? _selectedCustomer;
  // Save-semantics flag (OPS-1): sends customerId (incl. null to unlink) when
  // the user touched the customer selection. Not customer state.
  bool _customerTouched = false;
  int _currentStage = 1;

  // DG-304 Phase 5: admin staff assignment state for the delivery stage
  // dropdown (FR8/AC5). `_assignedStaffTouched` gates whether the value is
  // sent on save (incl. null to unassign — FR6), mirroring `customerTouched`.
  String? _assignedStaffId;
  bool _assignedStaffTouched = false;

  /// FR2/FR3: the delivery phone syncs with the customer phone until the user
  /// manually makes them differ; once diverged it stays independent for the
  /// rest of the edit session.
  bool _deliveryPhoneDiverged = false;

  /// Re-entrancy guard set while syncing the delivery phone from the customer
  /// phone so the delivery-phone listener does not treat the sync as a manual
  /// edit and flip [_deliveryPhoneDiverged].
  bool _syncingDeliveryPhone = false;

  /// Guards controller writes performed during [_initFrom] so the sync
  /// listeners do not run against partially-initialized state.
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _phoneCtrl.addListener(_onCustomerPhoneChanged);
    _deliveryPhoneCtrl.addListener(_onDeliveryPhoneChanged);
  }

  @override
  void dispose() {
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

  /// FR2: while the delivery phone has not been manually diverged, every
  /// customer-phone change also updates the delivery phone so the two stay
  /// in sync.
  void _onCustomerPhoneChanged() {
    if (_initializing || _deliveryPhoneDiverged) return;
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
      _deliveryPhoneDiverged = true;
    }
  }

  void _initFrom(Order order) {
    if (_initialized) return;
    _initialized = true;
    _initializing = true;
    _nameCtrl.text = order.customerName;
    _phoneCtrl.text = formatPhone(order.customerPhone);
    _addressCtrl.text = order.deliveryAddress;
    _deliveryPhoneCtrl.text = formatPhone(order.deliveryPhone);
    _notesCtrl.text = order.notes;
    _source = order.source;
    _deliveryType = order.deliveryType;
    _shippingFee = order.shippingFee;
    // FR9: load the existing linked customer from `order.customerId`.
    if (order.customerId != null) _loadLinkedCustomer(order.customerId!);
    // FR7: prefill delivery phone from customer phone for all delivery types
    // when empty (CQ-2: aligns the edit flow with the create flow, which
    // auto-fills for every type rather than only bus/door).
    if (_deliveryPhoneCtrl.text.trim().isEmpty &&
        _phoneCtrl.text.trim().isNotEmpty) {
      _deliveryPhoneCtrl.text = _phoneCtrl.text.trim();
    }
    // FR2/FR3: an order whose stored delivery phone already differs from the
    // customer phone starts diverged so the user's prior manual override is
    // preserved across the edit session.
    _deliveryPhoneDiverged =
        stripNonDigits(_deliveryPhoneCtrl.text) !=
            stripNonDigits(_phoneCtrl.text) &&
            _deliveryPhoneCtrl.text.trim().isNotEmpty;
    _dueDate = parseDueDate(order.dueDate);
    _dueTime = parseDueTime(order.dueTime);
    // DG-303 Phase 4: prefill GPS + time slot fields from the existing order.
    // DG-329 Phase 7 / FR9: Lat/Long are no longer editable in the wizard;
    // preserve the stored values verbatim for save.
    _existingLatitude = order.latitude;
    _existingLongitude = order.longitude;
    _existingGoogleMapsUrl = order.googleMapsUrl;
    // DG-304 Phase 5: prefill the staff assignment from the existing order so
    // the dropdown shows the current assignee (FR8/AC5).
    _assignedStaffId = order.assignedStaffId;
    _initializing = false;
  }

  Future<void> _loadLinkedCustomer(int customerId) async {
    try {
      final customerSvc = ref.read(customerServiceProvider);
      final customer = await customerSvc.getCustomer(customerId);
      if (mounted) setState(() => _selectedCustomer = customer);
    } catch (e) {
      debugPrint('[OrderEdit] load linked customer failed: $e');
    }
  }

  bool get _needsAddress => _deliveryType == 'bus' || _deliveryType == 'door';

  String _formatTime(TimeOfDay t) => formatHourMinute(t.hour, t.minute);

  void _updateShippingFeeForDeliveryType(
    String type, {
    required double busDefault,
    required double doorDefault,
  }) {
    setState(() {
      _deliveryType = type;
      _shippingFee = shippingFeeForDeliveryType(
        type,
        busDefault: busDefault,
        doorDefault: doorDefault,
      );
    });
  }

  void _setShippingFee(double fee) {
    setState(() => _shippingFee = fee);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => HourPickerDialog(initialHour: _dueTime?.hour ?? 8),
    );
    if (picked != null) {
      setState(() => _dueTime = TimeOfDay(hour: picked, minute: 0));
    }
  }

  void _goToStage(int stage) {
    setState(() => _currentStage = stage);
    _pageController.animateToPage(
      stage - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final originalOrder = ref.read(orderDetailProvider(widget.orderRef)).value;
    final newDueDate = _dueDate != null ? formatApiDate(_dueDate!) : null;
    String? publicCodeDateChangeDecision;
    if (shouldAskPublicCodeDateDecision(originalOrder, newDueDate)) {
      publicCodeDateChangeDecision =
          await showPublicCodeDateChangeDecision(context);
      if (publicCodeDateChangeDecision == null) return;
    }

    // FR1: auto-create-and-link a customer when name+phone present, no link.
    final created = await maybeAutoCreateCustomer(
      selectedCustomer: _selectedCustomer,
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      customerService: ref.read(customerServiceProvider),
    );
    if (created.customer != null && created.customer!.id != _selectedCustomer?.id) {
      _selectedCustomer = created.customer;
    }
    if (created.touched) _customerTouched = true;
    // CQ-6: surface a non-blocking notice when auto-create failed so the
    // operator knows the order will save without a linked customer.
    if (created.failed && mounted) {
      showTopSnackBar(context, CustomersLabels.autoCreateFailedNotice);
    }
    final customerId = _selectedCustomer?.id;

    // FR2: empty customer name defaults to `Khách lẻ` at save time only.
    final effectiveName = _nameCtrl.text.trim().isEmpty
        ? OrdersLabels.khachLe
        : _nameCtrl.text.trim();

    setState(() => _saving = true);
    late final Order updatedOrder;
    try {
      updatedOrder = await ref
          .read(orderDetailProvider(widget.orderRef).notifier)
          .save(
            notes: _notesCtrl.text.trim(),
            dueDate: newDueDate,
            dueTime: _dueTime != null ? _formatTime(_dueTime!) : null,
            customerPhone: _phoneCtrl.text.trim(),
            deliveryAddress: _needsAddress ? _addressCtrl.text.trim() : '',
            deliveryPhone: _needsAddress ? _deliveryPhoneCtrl.text.trim() : '',
            deliveryType: _deliveryType,
            source: _source.isEmpty ? null : _source,
            customerName: effectiveName,
            customerId: customerId,
            // OPS-1: send customerId (incl. null to unlink) when touched.
            customerTouched: _customerTouched,
            shippingFee: _shippingFee,
            publicCodeDateChangeDecision: publicCodeDateChangeDecision,
            latitude: _existingLatitude,
            longitude: _existingLongitude,
            googleMapsUrl: _existingGoogleMapsUrl,
            // DG-306 Phase 1 / FR1: auto-derive the slot from `_dueTime`.
            deliveryTimeSlot: _dueTime != null
                ? deriveTimeSlot(_formatTime(_dueTime!))
                : null,
            // DG-304 Phase 5: admin staff assignment (FR8/AC5). Only sent when
            // the admin touched the dropdown; null clears the assignment.
            assignedStaffId: _assignedStaffId,
            assignedStaffTouched: _assignedStaffTouched,
          );
    } catch (e, stackTrace) {
      debugPrint('order_edit: save failed for ${widget.orderRef}: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        showTopSnackBar(context, normalizeApiError(e).message);
      }
      if (mounted) setState(() => _saving = false);
      return;
    }
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
      setState(() => _saving = false);
    }
  }

  OrderWizardData get _wizardSnapshot => OrderWizardData(
        customerName: _nameCtrl.text,
        customerPhone: _phoneCtrl.text,
        selectedCustomer: _selectedCustomer,
        deliveryType: _deliveryType,
        deliveryAddress: _addressCtrl.text,
        deliveryPhone: _deliveryPhoneCtrl.text,
        shippingFee: _shippingFee,
        notes: _notesCtrl.text,
        source: _source,
        latitude: _existingLatitude,
        longitude: _existingLongitude,
        googleMapsUrl: _existingGoogleMapsUrl,
      );

  /// DG-375 Phase 4.3 / FR3 / AC3: opens the template picker modal filled
  /// from the current edit-wizard state + the saved order's codes. Used by
  /// the overflow menu and the review-stage button.
  void _openTemplatePicker() {
    final order = ref.read(orderDetailProvider(widget.orderRef)).asData?.value;
    if (order == null) return;
    final workItemsAsync =
        ref.read(orderWorkItemsProvider(widget.orderRef));
    final summaryItems =
        summaryItemsFromWorkItems(workItemsAsync.value ?? const []);
    final ctx = buildTemplateContextFromEditWizard(
      order: order,
      summaryItems: summaryItems,
      wizardSnapshot: _wizardSnapshot,
      dueDate: _dueDate,
      dueTime: _dueTime,
      createdBy: ref.read(loggedByProvider),
    );
    TemplatePickerModal.show(context, templateContext: ctx);
  }

  void _onCustomerSelected(Customer? c) {
    setState(() {
      _selectedCustomer = c;
      _customerTouched = true;
      if (c != null) {
        _nameCtrl.text = c.name;
        if (c.phone.isNotEmpty) _phoneCtrl.text = formatPhone(c.phone);
      }
    });
  }

  void _onClearCustomerSelection() {
    setState(() {
      if (_selectedCustomer != null) {
        _selectedCustomer = null;
        _customerTouched = true;
      }
    });
  }

  /// DG-304 Phase 5: admin selects a delivery staff member (or clears to
  /// unassign) in the wizard delivery stage dropdown (FR8/FR6/AC5).
  void _onAssignedStaffChanged(String? staffId) {
    setState(() {
      _assignedStaffId = staffId;
      _assignedStaffTouched = true;
    });
  }

  /// DG-385 Phase 4 / FR2 / AC2 / AC7: auto-bind the selected suggestion's
  /// `googleMapsUrl` to the order being edited. The address text is written
  /// into the address controller by the autocomplete field; this callback
  /// only updates the stored map link and clears stale GPS coordinates so
  /// the saved order does not carry mismatched address/coords. Edit-flow
  /// parity with order creation (FR9/AC7).
  void _onAddressSelected(AddressSuggestion suggestion) {
    setState(() {
      _existingGoogleMapsUrl = suggestion.googleMapsUrl;
      _existingLatitude = null;
      _existingLongitude = null;
    });
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(OrdersLabels.editOrder),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _goToStage(4),
            child: _saving
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
          final workItemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));
          final summaryItems =
              summaryItemsFromWorkItems(workItemsAsync.value ?? const []);
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: OrderStageIndicator(
                    currentStage: _currentStage,
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
                        selectedCustomer: _selectedCustomer,
                        onSelectedCustomer: _onCustomerSelected,
                        onClearSelection: _onClearCustomerSelection,
                        nameCtrl: _nameCtrl,
                        phoneCtrl: _phoneCtrl,
                        source: _source,
                        onSourceChanged: (s) => setState(() => _source = s),
                        wizardSnapshot: _wizardSnapshot,
                        summaryItems:
                            summaryItems.where((i) => !i.isExtra).toList(),
                        onBack: () => _goToStage(1),
                        onContinue: () => _goToStage(3),
                      ),
                      EditStage3Delivery(
                        deliveryType: _deliveryType,
                        shippingFee: _shippingFee,
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
                        dueDate: _dueDate,
                        dueTime: _dueTime,
                        onPickDate: _pickDate,
                        onPickTime: _pickTime,
                        onDueTimeChanged: (t) => setState(() => _dueTime = t),
                        wizardSnapshot: _wizardSnapshot,
                        summaryItems: summaryItems,
                        onBack: () => _goToStage(2),
                        onContinue: () => _goToStage(4),
                        // DG-304 Phase 5: staff assignment dropdown state.
                        assignedStaffId: _assignedStaffId,
                        onAssignedStaffChanged: _onAssignedStaffChanged,
                        // DG-385 Phase 4 / FR5/FR2/AC5/AC7: customer id for
                        // customer-prioritized suggestions + auto-bind map
                        // link on selection (edit-flow parity with create).
                        customerId: _selectedCustomer?.id,
                        onAddressSelected: _onAddressSelected,
                      ),
                      EditStage4Review(
                        orderRef: widget.orderRef,
                        wizardSnapshot: _wizardSnapshot,
                        summaryItems: summaryItems,
                        dueDate: _dueDate,
                        dueTime: _dueTime,
                        onSave: _save,
                        onBack: () => _goToStage(3),
                        isProcessing: _saving,
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