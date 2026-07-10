// DG-211 Phase 5: single-state customer model + stage-widget decomposition
// (coordinator delegates stage bodies to widgets/order_edit/edit_stageN_*).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/customer_service.dart';
import '../../data/models/customer.dart';
import '../../data/models/order.dart';
import '../../providers/order_providers.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/api_error.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'order_edit/utils/edit_public_code_dialog.dart';
import 'order_edit/utils/edit_save_helpers.dart';
import 'order_edit/utils/edit_summary_helpers.dart';
import 'widgets/hour_picker.dart';
import 'widgets/order_stage_indicator.dart';
import 'widgets/order_wizard.dart';
import 'widgets/order_edit/edit_stage1_product.dart';
import 'widgets/order_edit/edit_stage2_customer.dart';
import 'widgets/order_edit/edit_stage3_delivery.dart';
import 'widgets/order_edit/edit_stage4_review.dart';

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
  // FR9: single-state customer model (was tri-state: _selectedCustomer +
  // _linkedCustomerId + _customerTouched). The existing linked customer is
  // loaded from `order.customerId` into `_selectedCustomer` on open.
  Customer? _selectedCustomer;
  // Save-semantics flag (OPS-1): sends customerId (incl. null to unlink) when
  // the user touched the customer selection. Not customer state.
  bool _customerTouched = false;
  int _currentStage = 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _initFrom(Order order) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = order.customerName;
    _phoneCtrl.text = order.customerPhone;
    _addressCtrl.text = order.deliveryAddress;
    _deliveryPhoneCtrl.text = order.deliveryPhone;
    _notesCtrl.text = order.notes;
    _source = order.source;
    _deliveryType = order.deliveryType;
    _shippingFee = order.shippingFee;
    // FR9: load the existing linked customer from `order.customerId`.
    if (order.customerId != null) _loadLinkedCustomer(order.customerId!);
    // FR7: prefill delivery phone from customer phone for bus/door when empty.
    if ((order.deliveryType == 'bus' || order.deliveryType == 'door') &&
        _deliveryPhoneCtrl.text.trim().isEmpty &&
        _phoneCtrl.text.trim().isNotEmpty) {
      _deliveryPhoneCtrl.text = _phoneCtrl.text.trim();
    }
    _dueDate = parseDueDate(order.dueDate);
    _dueTime = parseDueTime(order.dueTime);
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
        ? VN.khachLe
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
      );

  void _onCustomerSelected(Customer? c) {
    setState(() {
      _selectedCustomer = c;
      _customerTouched = true;
      if (c != null) {
        _nameCtrl.text = c.name;
        if (c.phone.isNotEmpty) _phoneCtrl.text = c.phone;
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

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderRef));
    final fees = shippingFeeDefaults(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.editOrder),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _goToStage(4),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(VN.save),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text(VN.apiError)),
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