// EXEMPT: 300-line threshold exceeded: screen coordinator above threshold because shared 4-stage PageView wizard orchestration, edit-form state synchronization, and submit guards are tightly coupled in-place. Extraction of stage bodies requires dedicated regression window to validate edit-mode state preservation across wizard stages. Reviewed 2026-07-08.
// DG-211 Phase 5: converted to 4-stage PageView wizard matching OrderCreateScreen pattern.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/customer_service.dart';
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
import 'widgets/order_delivery_section.dart';
import 'widgets/order_photo_section.dart';
import 'widgets/order_stage_indicator.dart';
import 'widgets/order_wizard.dart';
import 'widgets/product_picker_page.dart';
import 'widgets/section_header.dart';
import 'widgets/stage1_empty_state.dart';
import 'widgets/stage1_responsive_content.dart';
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
    // FR7: prefill delivery phone from customer phone for bus/door when the
    // delivery phone is empty (mirror stage3_delivery_options_screen.dart:97-111).
    if ((order.deliveryType == 'bus' || order.deliveryType == 'door') &&
        _deliveryPhoneCtrl.text.trim().isEmpty &&
        _phoneCtrl.text.trim().isNotEmpty) {
      _deliveryPhoneCtrl.text = _phoneCtrl.text.trim();
    }
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

    // FR1: auto-create-and-link a customer when name+phone are present but no
    // customer is linked. Mirrors order_create_screen.dart:137-151. No dedup
    // (matches create behavior per §16).
    var customerId = _selectedCustomer?.id;
    if (customerId == null &&
        _nameCtrl.text.trim().isNotEmpty &&
        _phoneCtrl.text.trim().isNotEmpty) {
      try {
        final customerSvc = ref.read(customerServiceProvider);
        final result = await customerSvc.createCustomer(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
        );
        customerId = result.customer.id;
        _selectedCustomer = result.customer;
        _customerTouched = true;
      } catch (e) {
        debugPrint('[OrderEdit] auto-create-customer failed: $e');
      }
    }

    // FR2: customer name is optional in edit; empty name defaults to `Khách lẻ`
    // (VN walk-in fallback label) at save time only. The UI field stays empty.
    final effectiveName = _nameCtrl.text.trim().isEmpty
        ? VN.khachLe
        : _nameCtrl.text.trim();

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
            customerName: effectiveName,
            customerId: customerId,
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

  /// Converts a [WorkItem] (server-side work item) into a [DraftOrderItem]
  /// with a minimal [Product] stub so the summary cards can render the
  /// edit-order summary cards with real data. The summary cards only read
  /// `product.name`, `quantity`, `unitPrice`, `isExtra`, and `isGift`, so a
  /// minimal stub is sufficient (FB-6).
  DraftOrderItem _workItemToDraft(WorkItem w) {
    final stub = Product(
      id: int.tryParse(w.productId) ?? 0,
      name: w.productName,
      basePrice: w.unitPrice,
    );
    return DraftOrderItem(
      product: stub,
      quantity: w.quantity,
      notes: w.notes,
      isBirthday: w.isBirthday,
      isExtra: w.isExtra,
      isGift: w.isGift,
      attributes: Map<String, dynamic>.from(w.attributes),
    );
  }

  List<DraftOrderItem> _summaryItems(List<WorkItem> workItems) {
    return workItems.map(_workItemToDraft).toList();
  }

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
          final workItemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));
          final summaryItems = _summaryItems(workItemsAsync.value ?? const []);
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
                      _buildStage1Product(order),
                      _buildStage2Customer(
                        sourcesAsync,
                        summaryItems.where((i) => !i.isExtra).toList(),
                      ),
                      _buildStage3Delivery(
                        shippingBusDefault,
                        shippingDoorDefault,
                        summaryItems,
                      ),
                      _buildStage4Review(order, summaryItems),
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
  // FR11/FR14: aligned with create's Stage 1 layout — wrapped in
  // `Stage1ResponsiveContent`, shows a `Stage1EmptyState` matching create when
  // no WorkItems exist, and uses the shared `SectionHeader`. Edit-specific
  // `_WorkItemsSection`/`_EditExtrasSection` behavior is preserved; server-side
  // WorkItems remain the data source.
  Widget _buildStage1Product(Order order) {
    final workItemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));
    final workItems = workItemsAsync.value ?? const <WorkItem>[];
    final hasRegular = workItems.any((i) => !i.isExtra);
    final hasExtras = workItems.any((i) => i.isExtra);
    // Only show the empty state once the work items have loaded and are
    // truly empty. During the initial load (`value` is null) we render the
    // content scaffold so the empty state does not flash before data arrives
    // (mirrors create's loading-then-content flow).
    final isLoaded = workItemsAsync.hasValue;
    final isEmpty = isLoaded && !hasRegular && !hasExtras;

    if (isEmpty) {
      return Column(
        children: [
          Expanded(
            child: Stage1EmptyState(onAddProduct: _openProductPicker),
          ),
          _buildStageNavigation(
            onBack: null,
            onContinue: () => _goToStage(2),
            continueLabel: OrdersLabels.continueLabel,
          ),
        ],
      );
    }

    return Stage1ResponsiveContent(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(VN.workItemsSection),
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
      ),
    );
  }

  // ── Stage 2: Customer (name, phone, source) ─────────────────────────
  Widget _buildStage2Customer(
    AsyncValue<List<String>> sourcesAsync,
    List<DraftOrderItem> summaryItems,
  ) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(VN.customer),
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
                const SectionHeader(VN.orderSource),
                _buildSourceSelector(sourcesAsync),
                ProductSummaryCard(items: summaryItems),
                CustomerSummaryCard(
                  wizardData: _wizardSnapshot,
                  source: _source,
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
  // Uses the canonical shared OrderDeliverySection (DG-216 Phase 3). Edit-specific
  // features — the formatDisplayDate date label, the HourPickerDialog time picker,
  // and HourPresetChips — are preserved via the composable `dueDateTimeSlot`.
  Widget _buildStage3Delivery(
    double shippingBusDefault,
    double shippingDoorDefault,
    List<DraftOrderItem> summaryItems,
  ) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: OrderDeliverySection(
              mode: OrderDeliverySectionMode.editable,
              useResponsiveLayout: true,
              deliveryType: _deliveryType,
              shippingFee: _shippingFee,
              addressCtrl: _addressCtrl,
              phoneCtrl: _deliveryPhoneCtrl,
              phoneInputFormatters: [PhoneInputFormatter()],
              notesCtrl: _notesCtrl,
              shippingBusDefault: shippingBusDefault,
              shippingDoorDefault: shippingDoorDefault,
              onDeliveryTypeChanged: (type) {
                // FR7: prefill delivery phone from customer phone for bus/door
                // when the delivery phone is empty; never overwrite a
                // user-entered value.
                if (type == 'bus' || type == 'door') {
                  if (_deliveryPhoneCtrl.text.trim().isEmpty &&
                      _phoneCtrl.text.trim().isNotEmpty) {
                    _deliveryPhoneCtrl.text = _phoneCtrl.text.trim();
                  }
                }
                _updateShippingFeeForDeliveryType(
                  type,
                  busDefault: shippingBusDefault,
                  doorDefault: shippingDoorDefault,
                );
              },
              onShippingFeeChanged: _setShippingFee,
              dueDate: _dueDate,
              dueTime: _dueTime,
              dueDateTimeSlot: _buildEditDueDateTime(),
              summaryCardSlots: [
                ProductSummaryCard(items: summaryItems),
                CustomerSummaryCard(
                  wizardData: _wizardSnapshot,
                  source: _source,
                ),
                DeliverySummaryCard(
                  wizardData: _wizardSnapshot,
                  dueDate: _dueDate,
                  dueTime: _dueTime,
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

  // Edit-specific due date/time controls: date label uses formatDisplayDate,
  // time uses the hour-only HourPickerDialog (F5), and HourPresetChips offer
  // quick time-slot selection. Passed to OrderDeliverySection.dueDateTimeSlot.
  Widget _buildEditDueDateTime() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  _dueDate != null ? formatDisplayDate(_dueDate) : VN.dueDate,
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
                  _dueTime != null ? _formatTime(_dueTime!) : VN.dueTime,
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
      ],
    );
  }

  // ── Stage 4: Review (summary + order photos + save) ─────────────────
  // FR13/FR14: aligned with create's Stage 4 layout — wrapped in
  // `Stage1ResponsiveContent`, uses the shared `SectionHeader` for the review
  // title (replacing the inline `Text`), and preserves the order-level
  // `OrderPhotoSection`.
  Widget _buildStage4Review(Order order, List<DraftOrderItem> summaryItems) {
    return Column(
      children: [
        Expanded(
          child: Stage1ResponsiveContent(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(OrdersLabels.reviewSummary),
                  Text(
                    OrdersLabels.checkoutReviewHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 16),
                  ProductSummaryCard(items: summaryItems),
                  CustomerSummaryCard(
                    wizardData: _wizardSnapshot,
                    source: _source,
                  ),
                  DeliverySummaryCard(
                    wizardData: _wizardSnapshot,
                    dueDate: _dueDate,
                    dueTime: _dueTime,
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader(VN.orderPhotos),
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

  // FR6: grouped two-row source selector mirroring create's
  // stage2_customer_info_screen.dart:143-193. TaiTiem/walkInCustomer auto-fill
  // logic is intentionally removed to match create's simple toggle pattern.
  static const _defaultSources = [
    OrdersLabels.sourceFbDoangia,
    OrdersLabels.sourceFbPageMoi,
    OrdersLabels.sourceZalo,
    OrdersLabels.sourceDienThoai,
    OrdersLabels.sourceTaiTiem,
  ];

  Widget _buildSourceSelector(AsyncValue<List<String>> sourcesAsync) {
    return sourcesAsync.when(
      data: (srcList) {
        final sources = srcList.isNotEmpty ? srcList : _defaultSources;
        final row1 = sources.where((s) =>
            s == OrdersLabels.sourceFbDoangia ||
            s == OrdersLabels.sourceFbPageMoi).toList();
        final row2 = sources.where((s) =>
            s == OrdersLabels.sourceZalo ||
            s == OrdersLabels.sourceDienThoai ||
            s == OrdersLabels.sourceTaiTiem).toList();
        return Column(
          children: [
            if (row1.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 8,
                  children: row1
                      .map((s) => ChoiceChip(
                            label: Text(s),
                            selected: _source == s,
                            onSelected: (_) => setState(() =>
                                _source = _source == s ? '' : s),
                          ))
                      .toList(),
                ),
              ),
            if (row2.isNotEmpty)
              Wrap(
                spacing: 8,
                children: row2
                    .map((s) => ChoiceChip(
                          label: Text(s),
                          selected: _source == s,
                          onSelected: (_) => setState(() =>
                              _source = _source == s ? '' : s),
                        ))
                    .toList(),
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
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