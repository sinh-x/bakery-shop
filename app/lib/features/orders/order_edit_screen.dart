// EXEMPT: 300-line threshold exceeded: screen coordinator above threshold because shared 4-stage PageView wizard orchestration, edit-form state synchronization, and submit guards are tightly coupled in-place. Extraction of stage bodies requires dedicated regression window to validate edit-mode state preservation across wizard stages. Reviewed 2026-07-08.
// DG-211 Phase 5: converted to 4-stage PageView wizard matching OrderCreateScreen pattern.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/models/customer.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/models/work_item.dart';
import '../../providers/config_provider.dart';
import '../../providers/order_providers.dart';
import '../../providers/products_provider.dart';
import '../../shared/utils/config_parsers.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/order_helpers.dart';
import '../../shared/utils/phone_formatter.dart';
import '../../shared/utils/api_error.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'utils/trung_bay_inventory_extensions.dart';
import 'widgets/hour_picker.dart';
import 'widgets/order_customer_section.dart';
import 'widgets/order_photo_section.dart';
import 'widgets/order_stage_indicator.dart';
import 'widgets/order_wizard.dart';
import 'widgets/product_picker_page.dart';
import 'widgets/stage_summary_card.dart';

part 'order_edit/widgets/edit_extras_section.dart';
part 'order_edit/widgets/work_item_edit_card.dart';
part 'order_edit/widgets/work_items_section.dart';

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
  Customer? _selectedCustomer;
  int? _linkedCustomerId;
  bool _customerTouched = false;
  int _currentStage = 1;

  final _pendingNewItems = <DraftOrderItem>[];

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
    _linkedCustomerId = order.customerId;
    if (order.dueDate != null) {
      final parsed = parseApiDate(order.dueDate);
      if (parsed != null) {
        _dueDate = parsed;
      } else {
        debugPrint('order_edit: invalid due date "${order.dueDate}"');
      }
    }
    if (order.dueTime != null) {
      final parts = order.dueTime!.split(':');
      if (parts.length == 2) {
        _dueTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
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
      switch (type) {
        case 'bus':
          _shippingFee = busDefault;
          break;
        case 'door':
          _shippingFee = doorDefault;
          break;
        case 'pickup':
        default:
          _shippingFee = 0;
          break;
      }
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

  // F5: Hour picker (replaces showTimePicker)
  Future<void> _pickTime() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => HourPickerDialog(initialHour: _dueTime?.hour ?? 8),
    );
    if (picked != null) {
      setState(() => _dueTime = TimeOfDay(hour: picked, minute: 0));
    }
  }

  Future<void> _openProductPicker() async {
    _pendingNewItems.clear();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductPickerPage(
          selectedItems: _pendingNewItems,
          onChanged: _commitNewItems,
        ),
      ),
    );
  }

  void _commitNewItems() {
    final toAdd = List<DraftOrderItem>.from(_pendingNewItems);
    for (final draft in toAdd) {
      ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .add(
            productName: draft.product.name,
            productId: draft.product.productCode,
            quantity: draft.quantity,
            unitPrice: draft.unitPrice,
            notes: draft.notes,
            attributes: draft.attributes,
            priceChipId: draft.priceChipId,
          );
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
    final dueDateChanged = originalOrder != null && newDueDate != originalOrder.dueDate;
    final shouldAskDateDecision =
        dueDateChanged && (originalOrder.publicOrderCode.trim().isNotEmpty);
    String? publicCodeDateChangeDecision;
    if (shouldAskDateDecision) {
      publicCodeDateChangeDecision = await _promptPublicCodeDateDecision();
      if (publicCodeDateChangeDecision == null) return;
    }

    setState(() => _saving = true);
    try {
      final updatedOrder = await ref
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
            customerName: _nameCtrl.text.trim(),
            customerId: _selectedCustomer?.id,
            // OPS-1: when the user touched the customer selection (including
            // clearing it), always send customerId to the backend so an unlink
            // (null) propagates instead of being omitted as "unchanged".
            customerTouched: _customerTouched,
            shippingFee: _shippingFee,
            publicCodeDateChangeDecision: publicCodeDateChangeDecision,
          );
      final oldVisualCode = visualOrderCode(
        orderRef: originalOrder?.orderRef ?? widget.orderRef,
        publicOrderCode: originalOrder?.publicOrderCode,
      );
      final newVisualCode = visualOrderCode(
        orderRef: updatedOrder.orderRef,
        publicOrderCode: updatedOrder.publicOrderCode,
      );
      if (mounted) {
        if (oldVisualCode != newVisualCode) {
          showTopSnackBar(context, '${VN.publicCodeChangedNotice} $newVisualCode');
        }
        showTopSnackBar(context, VN.orderEditSaved);
        context.pop();
      }
    } catch (e, stackTrace) {
      debugPrint('order_edit: save failed for ${widget.orderRef}: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        showTopSnackBar(context, normalizeApiError(e).message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _promptPublicCodeDateDecision() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.publicCodeDateChangeTitle),
        content: const Text(VN.publicCodeDateChangePrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(VN.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('keep'),
            child: const Text(VN.publicCodeKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('regenerate'),
            child: const Text(VN.publicCodeRegenerate),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderRef));
    final sourcesAsync = ref.watch(orderSourcesProvider); // F1
    final shippingBusAsync = ref.watch(shippingFeeBusProvider);
    final shippingDoorAsync = ref.watch(shippingFeeDoorProvider);
    final double shippingBusDefault = shippingBusAsync.when(
      data: (values) => firstFeeOrFallback(values, 25000),
      loading: () => 25000,
      error: (_, _) => 25000,
    );
    final double shippingDoorDefault = shippingDoorAsync.when(
      data: (values) => firstFeeOrFallback(values, 20000),
      loading: () => 20000,
      error: (_, _) => 20000,
    );

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
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: OrderStageIndicator(currentStage: _currentStage),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildStage1Product(order),
                      _buildStage2Customer(sourcesAsync),
                      _buildStage3Delivery(
                        shippingBusDefault,
                        shippingDoorDefault,
                      ),
                      _buildStage4Review(order),
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

  // ── Stage 1: Product (work items + extras) ──────────────────────────
  Widget _buildStage1Product(Order order) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader(VN.workItemsSection),
                _WorkItemsSection(
                  orderRef: widget.orderRef,
                  onAddTap: _openProductPicker,
                ),
                const SizedBox(height: 20),
                _EditExtrasSection(orderRef: widget.orderRef),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        _buildStageNavigation(
          onBack: null,
          onContinue: () => _goToStage(2),
          continueLabel: OrdersLabels.continueLabel,
        ),
      ],
    );
  }

  // ── Stage 2: Customer (name, phone, source) ─────────────────────────
  Widget _buildStage2Customer(AsyncValue<List<String>> sourcesAsync) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader(VN.customer),
                OrderCustomerSection(
                  linkedCustomerId: _linkedCustomerId,
                  selectedCustomer: _selectedCustomer,
                  customerTouched: _customerTouched,
                  onSelected: (c) => setState(() {
                    _selectedCustomer = c;
                    _customerTouched = true;
                    if (c != null) {
                      _nameCtrl.text = c.name;
                      if (c.phone.isNotEmpty) _phoneCtrl.text = c.phone;
                    }
                  }),
                  onClearSelection: () => setState(() {
                    if (_selectedCustomer != null) {
                      _selectedCustomer = null;
                      _customerTouched = true;
                    }
                  }),
                  nameCtrl: _nameCtrl,
                  phoneCtrl: _phoneCtrl,
                ),
                const SizedBox(height: 20),
                const _SectionHeader(VN.orderSource),
                sourcesAsync.when(
                  data: (sources) => Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: sources
                        .map(
                          (s) => ChoiceChip(
                            label: Text(s),
                            selected: _source == s,
                            onSelected: (_) => setState(() {
                              final wasSelected = _source == s;
                              _source = wasSelected ? '' : s;
                              if (!wasSelected &&
                                  s == VN.sourceTaiTiem &&
                                  _nameCtrl.text.isEmpty) {
                                _nameCtrl.text = VN.walkInCustomer;
                              } else if (wasSelected &&
                                  s == VN.sourceTaiTiem &&
                                  _nameCtrl.text == VN.walkInCustomer) {
                                _nameCtrl.text = '';
                              }
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (e, st) => const SizedBox.shrink(),
                ),
                StageSummaryCard(
                  items: const [],
                  wizardData: _wizardSnapshot,
                  source: _source,
                  showProducts: false,
                  showCustomer: false,
                ),
              ],
            ),
          ),
        ),
        _buildStageNavigation(
          onBack: () => _goToStage(1),
          onContinue: () => _goToStage(3),
          continueLabel: OrdersLabels.continueLabel,
        ),
      ],
    );
  }

  // ── Stage 3: Delivery (type, address, phone, shipping fee, notes, due date) ──
  Widget _buildStage3Delivery(
    double shippingBusDefault,
    double shippingDoorDefault,
  ) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader(VN.deliveryType),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'pickup',
                      label: Text(VN.pickup),
                      icon: Icon(Icons.store, size: 16),
                    ),
                    ButtonSegment(
                      value: 'bus',
                      label: Text(VN.deliveryBus),
                      icon: Icon(Icons.directions_bus, size: 16),
                    ),
                    ButtonSegment(
                      value: 'door',
                      label: Text(VN.deliveryDoor),
                      icon: Icon(Icons.home, size: 16),
                    ),
                  ],
                  selected: {_deliveryType},
                  onSelectionChanged: (s) => _updateShippingFeeForDeliveryType(
                    s.first,
                    busDefault: shippingBusDefault,
                    doorDefault: shippingDoorDefault,
                  ),
                ),
                if (_needsAddress) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _deliveryPhoneCtrl,
                    decoration: const InputDecoration(
                      labelText: OrdersLabels.deliveryPhone,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneInputFormatter()],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: VN.deliveryAddress,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        _needsAddress && (v == null || v.trim().isEmpty)
                        ? VN.fieldRequired
                        : null,
                  ),
                ],
                const SizedBox(height: 20),
                if (_deliveryType == 'bus' || _deliveryType == 'door') ...[
                  const _SectionHeader(VN.shippingFee),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: _shippingFee >= 5000
                            ? () => _setShippingFee(_shippingFee - 5000.0)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _shippingFee == 0
                              ? VN.shippingFree
                              : formatVND(_shippingFee),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton.filled(
                        onPressed: () => _setShippingFee(_shippingFee + 5000.0),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: VN.notes,
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                const _SectionHeader(VN.dueDate),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _dueDate != null
                              ? formatDisplayDate(_dueDate)
                              : VN.dueDate,
                        ),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(
                          _dueTime != null
                              ? _formatTime(_dueTime!)
                              : VN.dueTime,
                        ),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                HourPresetChips(
                  selectedTime: _dueTime,
                  onSelected: (t) => setState(() => _dueTime = t),
                ),
                StageSummaryCard(
                  items: const [],
                  wizardData: _wizardSnapshot,
                  source: _source,
                  showProducts: false,
                  showCustomer: true,
                ),
              ],
            ),
          ),
        ),
        _buildStageNavigation(
          onBack: () => _goToStage(2),
          onContinue: () => _goToStage(4),
          continueLabel: OrdersLabels.continueLabel,
        ),
      ],
    );
  }

  // ── Stage 4: Review (summary + order photos + save) ─────────────────
  Widget _buildStage4Review(Order order) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  OrdersLabels.reviewSummary,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  OrdersLabels.checkoutReviewHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 16),
                StageSummaryCard(
                  items: const [],
                  wizardData: _wizardSnapshot,
                  source: _source,
                  dueDate: _dueDate,
                  dueTime: _dueTime,
                  showProducts: false,
                  showCustomer: true,
                  showDelivery: true,
                ),
                const SizedBox(height: 20),
                const _SectionHeader(VN.orderPhotos),
                OrderPhotoSection(
                  orderRef: widget.orderRef,
                  baseUrl: ref.watch(apiBaseUrlProvider),
                  orderLevelOnly: true,
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        _buildStageNavigation(
          onBack: () => _goToStage(3),
          onContinue: _save,
          continueLabel: VN.save,
          isProcessing: _saving,
        ),
      ],
    );
  }

  Widget _buildStageNavigation({
    VoidCallback? onBack,
    VoidCallback? onContinue,
    required String continueLabel,
    bool isProcessing = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (onBack != null)
            OutlinedButton(
              onPressed: onBack,
              child: const Text(OrdersLabels.backLabel),
            )
          else
            const SizedBox(width: 0),
          const Spacer(),
          FilledButton(
            onPressed: isProcessing ? null : onContinue,
            child: isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(continueLabel),
          ),
        ],
      ),
    );
  }
}