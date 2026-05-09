// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/api/api_client.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/models/work_item.dart';
import '../../providers/config_provider.dart';
import '../../providers/order_providers.dart';
import '../../providers/products_provider.dart';
import '../../shared/utils/config_parsers.dart';
import '../../shared/utils/phone_formatter.dart';
import '../../shared/utils/api_error.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/hour_picker.dart';
import 'widgets/order_photo_section.dart';
import 'widgets/product_picker_page.dart';

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
  final _notesCtrl = TextEditingController();

  String _source = '';
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _deliveryType = 'pickup';
  double _shippingFee = 0.0;
  bool _saving = false;
  bool _initialized = false;

  final _pendingNewItems = <DraftOrderItem>[];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _initFrom(Order order) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = order.customerName;
    _phoneCtrl.text = order.customerPhone;
    _addressCtrl.text = order.deliveryAddress;
    _notesCtrl.text = order.notes;
    _source = order.source;
    _deliveryType = order.deliveryType;
    _shippingFee = order.shippingFee;
    if (order.dueDate != null) {
      try {
        _dueDate = DateFormat('yyyy-MM-dd').parse(order.dueDate!);
      } catch (error, stackTrace) {
        debugPrint('order_edit: invalid due date "${order.dueDate}": $error');
        debugPrintStack(stackTrace: stackTrace);
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

  String _formatDateDisplay(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  String _formatDateApi(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
          );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(orderDetailProvider(widget.orderRef).notifier)
          .save(
            notes: _notesCtrl.text.trim(),
            dueDate: _dueDate != null ? _formatDateApi(_dueDate!) : null,
            dueTime: _dueTime != null ? _formatTime(_dueTime!) : null,
            customerPhone: _phoneCtrl.text.trim(),
            deliveryAddress: _needsAddress ? _addressCtrl.text.trim() : '',
            deliveryType: _deliveryType,
            source: _source.isEmpty ? null : _source,
            customerName: _nameCtrl.text.trim(),
            shippingFee: _shippingFee,
          );
      if (mounted) {
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
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(VN.save),
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(VN.apiError)),
        data: (order) {
          _initFrom(order);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                // ── Source (F1) ───────────────────────────────────────
                _SectionHeader(VN.orderSource),
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
                const SizedBox(height: 12),

                // ── Customer info ─────────────────────────────────────
                _SectionHeader(VN.customer),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: VN.customerName,
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? VN.fieldRequired : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: VN.customerPhone,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneInputFormatter()],
                ),
                const SizedBox(height: 20),

                // ── Schedule ──────────────────────────────────────────
                _SectionHeader(VN.dueDate),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _dueDate != null
                              ? _formatDateDisplay(_dueDate!)
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
                // F5: preset time chips
                HourPresetChips(
                  selectedTime: _dueTime,
                  onSelected: (t) => setState(() => _dueTime = t),
                ),
                const SizedBox(height: 20),

                // ── Delivery ──────────────────────────────────────────
                _SectionHeader(VN.deliveryType),
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

                // ── Shipping Fee ───────────────────────────────────────────
                if (_deliveryType == 'bus' || _deliveryType == 'door') ...[
                  _SectionHeader(VN.shippingFee),
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

                // ── Notes ─────────────────────────────────────────────
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

                // ── Work items ────────────────────────────────────────
                _SectionHeader(VN.workItemsSection),
                _WorkItemsSection(
                  orderRef: widget.orderRef,
                  onAddTap: _openProductPicker,
                ),
                const SizedBox(height: 20),

                // ── Extras section ────────────────────────────────────
                _EditExtrasSection(orderRef: widget.orderRef),
                const SizedBox(height: 20),

                // ── Order-level photos ────────────────────────────────
                OrderPhotoSection(
                  orderRef: widget.orderRef,
                  baseUrl: ref.watch(apiBaseUrlProvider),
                  orderLevelOnly: true,
                ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(VN.save),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

// ── Work items section ────────────────────────────────────────────────────────

class _WorkItemsSection extends ConsumerWidget {
  const _WorkItemsSection({required this.orderRef, required this.onAddTap});

  final String orderRef;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final workItemsAsync = ref.watch(orderWorkItemsProvider(orderRef));

    return workItemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('${VN.apiError}: $e'),
      data: (items) {
        final regularItems = items.where((i) => !i.isExtra).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...regularItems.map(
              (item) => _WorkItemEditCard(orderRef: orderRef, item: item),
            ),
            if (regularItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  VN.noWorkItems,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onAddTap,
              icon: const Icon(Icons.add, size: 16),
              label: const Text(VN.addProduct),
            ),
          ],
        );
      },
    );
  }
}

// ── Work item edit card ───────────────────────────────────────────────────────

class _WorkItemEditCard extends ConsumerStatefulWidget {
  const _WorkItemEditCard({required this.orderRef, required this.item});

  final String orderRef;
  final WorkItem item;

  @override
  ConsumerState<_WorkItemEditCard> createState() => _WorkItemEditCardState();
}

class _WorkItemEditCardState extends ConsumerState<_WorkItemEditCard> {
  bool _expanded = true;
  bool _isBirthday = false;
  bool _rutTien = false;
  late TextEditingController _notesCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _cashAmountCtrl;
  late TextEditingController _cashFeeCtrl;
  late FocusNode _notesFocus;
  late FocusNode _ageFocus;
  late FocusNode _priceFocus;
  late FocusNode _cashAmountFocus;
  late FocusNode _cashFeeFocus;

  static const int _defaultCashFee = 20000;
  static const int _cashFeeStep = 5000;
  static const int _cashAmountStep = 100000;
  static const int _minCashAmount = 100000;
  bool _editingCashAmount = false;
  // Preserved cash values for toggle-off (restored on toggle-on)
  String _savedCashAmount = '';
  String _savedCashFee = '';

  @override
  void initState() {
    super.initState();
    _isBirthday = widget.item.isBirthday;
    _notesCtrl = TextEditingController(text: widget.item.notes);
    _ageCtrl = TextEditingController(
      text: widget.item.age != null ? '${widget.item.age}' : '',
    );
    _priceCtrl = TextEditingController(
      text: widget.item.unitPrice.toInt().toString(),
    );
    // F15: Initialize rut tien state from attributes['rut_tien'] directly
    final cashAmount = widget.item.attributes['cash_amount']?.toString() ?? '';
    final cashFee = widget.item.attributes['cash_fee']?.toString() ?? '';
    _cashAmountCtrl = TextEditingController(text: cashAmount);
    _cashFeeCtrl = TextEditingController(
      text: cashFee.isNotEmpty ? cashFee : '$_defaultCashFee',
    );
    _rutTien = widget.item.attributes['rut_tien']?.toString() == 'true';
    _notesFocus = FocusNode()..addListener(_onNotesFocusChange);
    _ageFocus = FocusNode()..addListener(_onAgeFocusChange);
    _priceFocus = FocusNode()..addListener(_onPriceFocusChange);
    _cashAmountFocus = FocusNode()..addListener(_onCashAmountFocusChange);
    _cashFeeFocus = FocusNode()..addListener(_onCashFeeFocusChange);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _ageCtrl.dispose();
    _priceCtrl.dispose();
    _cashAmountCtrl.dispose();
    _cashFeeCtrl.dispose();
    _notesFocus.dispose();
    _ageFocus.dispose();
    _priceFocus.dispose();
    _cashAmountFocus.dispose();
    _cashFeeFocus.dispose();
    super.dispose();
  }

  void _onNotesFocusChange() {
    if (!_notesFocus.hasFocus) _editItem(notes: _notesCtrl.text);
  }

  void _onPriceFocusChange() {
    if (!_priceFocus.hasFocus) {
      final price = double.tryParse(_priceCtrl.text.trim());
      if (price != null) _editItem(unitPrice: price);
    }
  }

  void _onAgeFocusChange() {
    if (!_ageFocus.hasFocus && _isBirthday) {
      final age = int.tryParse(_ageCtrl.text.trim());
      _editItem(age: age);
    }
  }

  void _onCashAmountFocusChange() {
    if (!_cashAmountFocus.hasFocus) {
      _saveCashAttributes();
    }
  }

  void _onCashFeeFocusChange() {
    if (!_cashFeeFocus.hasFocus) {
      _saveCashAttributes();
    }
  }

  void _saveCashAttributes() {
    if (!_rutTien) return;
    final cashAmount = _cashAmountCtrl.text.trim();
    final cashFee = _cashFeeCtrl.text.trim();
    final attrs = <String, dynamic>{
      'rut_tien': 'true',
      'cash_amount': cashAmount,
      'cash_fee': cashFee.isNotEmpty ? cashFee : '$_defaultCashFee',
    };
    _editItem(attributes: attrs);
  }

  Future<void> _editItem({
    String? notes,
    double? unitPrice,
    bool? isBirthday,
    int? age,
    int? quantity,
    bool? isExtra,
    bool? isGift,
    Map<String, dynamic>? attributes,
  }) async {
    if (!mounted) return;
    try {
      await ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .edit(
            widget.item.id,
            notes: notes,
            unitPrice: unitPrice,
            isBirthday: isBirthday,
            age: age,
            quantity: quantity,
            isExtra: isExtra,
            isGift: isGift,
            attributes: attributes,
          );
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, normalizeApiError(e).message);
      }
    }
  }

  void _toggleGift() {
    _editItem(isGift: !widget.item.isGift);
  }

  Future<void> _confirmRemove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa sản phẩm?'),
        content: Text('Xóa "${widget.item.productName}" khỏi đơn hàng?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              VN.remove,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      try {
        await ref
            .read(orderWorkItemsProvider(widget.orderRef).notifier)
            .remove(widget.item.id);
      } catch (e) {
        if (mounted) {
          showTopSnackBar(context, '${VN.apiError}: $e');
        }
      }
    }
  }

  Product? _findProduct() {
    final products =
        ref.watch(productsProvider).asData?.value ?? const <Product>[];
    final pid = widget.item.productId;
    if (pid.isEmpty) return null;
    for (final p in products) {
      if (p.id.toString() == pid || p.productCode == pid) return p;
    }
    return null;
  }

  /// DG-092 §6 F7 / Q1: render one ChoiceChip row per enum attribute
  /// applicable to this product. Tap-to-change persists by sending the
  /// merged `attributes` map through the existing PATCH endpoint —
  /// `attributes` is replaced wholesale server-side, so we always send
  /// a copy of the current map with the updated key.
  List<Widget> _buildEnumChipSections(ThemeData theme) {
    final product = _findProduct();
    if (product == null) return const [];
    final result = <Widget>[];
    for (final ea in product.enumAttributes) {
      final activeOptions = ea.options
          .where((o) => o.active == 1)
          .toList(growable: false);
      if (activeOptions.isEmpty) continue;
      final selected = widget.item.attributes[ea.attributeType]?.toString();
      result.add(
        Text(
          ea.labelVi,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
      result.add(const SizedBox(height: 4));
      result.add(
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: activeOptions
              .map(
                (opt) => ChoiceChip(
                  label: Text(opt.valueVi),
                  selected: selected == opt.valueVi,
                  onSelected: (isSelected) {
                    if (!isSelected) return;
                    final next = Map<String, dynamic>.from(
                      widget.item.attributes,
                    );
                    next[ea.attributeType] = opt.valueVi;
                    _editItem(attributes: next);
                  },
                ),
              )
              .toList(),
        ),
      );
      result.add(const SizedBox(height: 8));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final workItemId = int.tryParse(item.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          // ── Header row ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName, style: theme.textTheme.bodyMedium),
                      Text(
                        formatVND(item.unitPrice),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                // Quantity +/- controls
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: item.quantity > 1
                      ? () => _editItem(quantity: item.quantity - 1)
                      : null,
                ),
                Text('${item.quantity}', style: theme.textTheme.bodyMedium),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () => _editItem(quantity: item.quantity + 1),
                ),
                // Gift toggle for extra items
                if (item.isExtra) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: VN.giftToggleTooltip,
                    child: InkWell(
                      onTap: _toggleGift,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: item.isGift
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: item.isGift
                                ? Colors.green
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.card_giftcard,
                              size: 14,
                              color: item.isGift ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              VN.giftBadge,
                              style: TextStyle(
                                fontSize: 11,
                                color: item.isGift ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                IconButton(
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: theme.colorScheme.error,
                  onPressed: _confirmRemove,
                ),
              ],
            ),
          ),

          // ── Expanded section ──────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Price
                  TextFormField(
                    controller: _priceCtrl,
                    focusNode: _priceFocus,
                    decoration: const InputDecoration(
                      labelText: VN.itemPrice,
                      border: OutlineInputBorder(),
                      suffixText: 'đ',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  // Enum attribute ChoiceChip rows (DG-092 F7 / Q1 — editable on edit)
                  ..._buildEnumChipSections(theme),
                  // Notes
                  TextFormField(
                    controller: _notesCtrl,
                    focusNode: _notesFocus,
                    decoration: const InputDecoration(
                      labelText: VN.notes,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  // Birthday checkbox
                  CheckboxListTile(
                    value: _isBirthday,
                    onChanged: (v) {
                      final newVal = v ?? false;
                      setState(() => _isBirthday = newVal);
                      _editItem(isBirthday: newVal);
                    },
                    title: const Text(VN.isBirthday),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  if (_isBirthday) ...[
                    TextFormField(
                      controller: _ageCtrl,
                      focusNode: _ageFocus,
                      decoration: const InputDecoration(
                        labelText: VN.birthdayAge,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                  ],
                  // F14: Rut tien toggle — only for items with rut_tien attribute
                  if (widget.item.attributes.containsKey('rut_tien')) ...[
                    CheckboxListTile(
                      value: _rutTien,
                      onChanged: (v) {
                        final newVal = v ?? false;
                        setState(() {
                          _rutTien = newVal;
                          _editingCashAmount = false;
                        });
                        if (!newVal) {
                          // Preserve cash values for restore on toggle-on
                          _savedCashAmount = _cashAmountCtrl.text.trim();
                          _savedCashFee = _cashFeeCtrl.text.trim();
                          _cashAmountCtrl.clear();
                          _cashFeeCtrl.clear();
                          _editItem(attributes: {});
                        } else {
                          // Restore saved values if any
                          if (_savedCashAmount.isNotEmpty) {
                            _cashAmountCtrl.text = _savedCashAmount;
                          }
                          if (_savedCashFee.isNotEmpty) {
                            _cashFeeCtrl.text = _savedCashFee;
                          }
                          _editItem(
                            attributes: {
                              'rut_tien': 'true',
                              'cash_amount': _cashAmountCtrl.text.trim(),
                              'cash_fee': _cashFeeCtrl.text.trim().isNotEmpty
                                  ? _cashFeeCtrl.text.trim()
                                  : '$_defaultCashFee',
                            },
                          );
                        }
                      },
                      title: Text(VN.rutTien),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    if (_rutTien) ...[
                      // F12: Cash amount stepper — same as create flow
                      Row(
                        children: [
                          Text('${VN.soTienRut}: '),
                          IconButton.filled(
                            onPressed: () {
                              final current =
                                  int.tryParse(_cashAmountCtrl.text) ?? 0;
                              if (current > _minCashAmount) {
                                final next = current - _cashAmountStep;
                                final clamped = next < _minCashAmount
                                    ? _minCashAmount
                                    : next;
                                setState(() {
                                  _cashAmountCtrl.text = '$clamped';
                                  _editingCashAmount = false;
                                });
                                _saveCashAttributes();
                              }
                            },
                            icon: const Icon(Icons.remove, size: 16),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _editingCashAmount = true),
                              child: _editingCashAmount
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: TextFormField(
                                        controller: _cashAmountCtrl,
                                        autofocus: true,
                                        textAlign: TextAlign.center,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          suffixText: 'đ',
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(9),
                                        ],
                                        onChanged: (_) => _saveCashAttributes(),
                                        onEditingComplete: () {
                                          final val =
                                              int.tryParse(
                                                _cashAmountCtrl.text,
                                              ) ??
                                              0;
                                          if (val < _minCashAmount &&
                                              val != 0) {
                                            _cashAmountCtrl.text =
                                                '$_minCashAmount';
                                          }
                                          _saveCashAttributes();
                                          setState(
                                            () => _editingCashAmount = false,
                                          );
                                        },
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        _cashAmountCtrl.text.isEmpty ||
                                                _cashAmountCtrl.text == '0'
                                            ? '0đ'
                                            : formatVND(
                                                (int.tryParse(
                                                          _cashAmountCtrl.text,
                                                        ) ??
                                                        0)
                                                    .toDouble(),
                                              ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                            ),
                          ),
                          IconButton.filled(
                            onPressed: () {
                              final current =
                                  int.tryParse(_cashAmountCtrl.text) ?? 0;
                              final next = current + _cashAmountStep;
                              final clamped = next < _minCashAmount
                                  ? _minCashAmount
                                  : next;
                              setState(() {
                                _cashAmountCtrl.text = '$clamped';
                                _editingCashAmount = false;
                              });
                              _saveCashAttributes();
                            },
                            icon: const Icon(Icons.add, size: 16),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('${VN.phiRutTien}: '),
                          IconButton.filled(
                            onPressed: () {
                              final current =
                                  int.tryParse(_cashFeeCtrl.text) ?? 0;
                              if (current >= _cashFeeStep) {
                                final next = current - _cashFeeStep;
                                _cashFeeCtrl.text = '$next';
                                _saveCashAttributes();
                              }
                            },
                            icon: const Icon(Icons.remove, size: 16),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              formatVND(
                                (int.tryParse(_cashFeeCtrl.text) ??
                                        _defaultCashFee)
                                    .toDouble(),
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton.filled(
                            onPressed: () {
                              final current =
                                  int.tryParse(_cashFeeCtrl.text) ??
                                  _defaultCashFee;
                              final next = current + _cashFeeStep;
                              _cashFeeCtrl.text = '$next';
                              _saveCashAttributes();
                            },
                            icon: const Icon(Icons.add, size: 16),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  // Per-item photos
                  if (workItemId != null) ...[
                    const SizedBox(height: 8),
                    OrderPhotoSection(
                      orderRef: widget.orderRef,
                      baseUrl: ref.watch(apiBaseUrlProvider),
                      workItemId: workItemId,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Extras section for edit screen ────────────────────────────────────────────

class _EditExtrasSection extends ConsumerWidget {
  const _EditExtrasSection({required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workItemsAsync = ref.watch(orderWorkItemsProvider(orderRef));
    final extrasAsync = ref.watch(orderExtrasProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(orderWorkItemsProvider(orderRef).notifier);

    return workItemsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (workItems) {
        final extras = workItems.where((i) => i.isExtra).toList();

        return extrasAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, st) => const SizedBox.shrink(),
          data: (extraValues) {
            final presets = <(String, double)>[];
            for (final v in extraValues) {
              final parts = v.split('|');
              if (parts.length == 2) {
                final name = parts[0].trim();
                final price = double.tryParse(parts[1].trim()) ?? 0;
                presets.add((name, price));
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(VN.extras),
                if (extras.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Chưa có phụ kiện',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                else
                  ...extras.map(
                    (extra) => _ExtraEditRow(
                      item: extra,
                      onIncrement: () async {
                        await notifier.edit(
                          extra.id,
                          quantity: extra.quantity + 1,
                        );
                      },
                      onDecrement: () async {
                        if (extra.quantity > 1) {
                          await notifier.edit(
                            extra.id,
                            quantity: extra.quantity - 1,
                          );
                        } else {
                          await notifier.remove(extra.id);
                        }
                      },
                      onToggleGift: () async {
                        await notifier.edit(extra.id, isGift: !extra.isGift);
                      },
                      onRemove: () async {
                        await notifier.remove(extra.id);
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                if (presets.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((preset) {
                      final (name, price) = preset;
                      return ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text('$name (${formatVND(price)})'),
                        onPressed: () async {
                          // Reuse existing paid item if same name
                          final existing = extras
                              .where((e) => e.productName == name && !e.isGift)
                              .firstOrNull;
                          if (existing != null) {
                            await notifier.edit(
                              existing.id,
                              quantity: existing.quantity + 1,
                            );
                          } else {
                            await notifier.add(
                              productName: name,
                              unitPrice: price,
                              isExtra: true,
                              isGift: false,
                            );
                          }
                        },
                      );
                    }).toList(),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ExtraEditRow extends StatelessWidget {
  const _ExtraEditRow({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleGift,
    required this.onRemove,
  });

  final WorkItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onToggleGift;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          // Gift/paid badge
          GestureDetector(
            onTap: onToggleGift,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: item.isGift
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: item.isGift ? Colors.green : Colors.grey.shade300,
                ),
              ),
                child: Text(
                item.isGift ? VN.giftBadge : VN.paymentFee,
                style: TextStyle(
                  fontSize: 10,
                  color: item.isGift ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Name + price
          Expanded(
            child: Text(
              '${item.productName} (${formatVND(item.unitPrice)})',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          // Qty +/-
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDecrement,
          ),
          Text('${item.quantity}', style: theme.textTheme.bodyMedium),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onIncrement,
          ),
          // Remove all
          IconButton(
            icon: Icon(Icons.close, size: 16, color: theme.colorScheme.error),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
