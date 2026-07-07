import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/order_service.dart';
import '../../data/api/payment_transaction_service.dart';
import '../../data/api/work_item_service.dart';
import '../../data/models/product.dart';
import '../../providers/config_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/order_providers.dart';
import '../../providers/products_provider.dart';
import '../../shared/gift_config.dart';
import '../../shared/utils/config_parsers.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/vnd_units.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'widgets/expandable_item_card.dart';
import 'widgets/hour_picker.dart';
import 'widgets/order_wizard.dart';
import 'widgets/product_picker_page.dart';
import 'widgets/section_header.dart';

class OrderCreateScreen extends ConsumerStatefulWidget {
  const OrderCreateScreen({super.key});

  @override
  ConsumerState<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends ConsumerState<OrderCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();

  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _source = '';

  bool _depositEnabled = false;
  final _depositAmountCtrl = TextEditingController();
  String _depositMethod = 'cash';

  final List<DraftOrderItem> _items = [];
  bool _submitting = false;
  bool _submitted = false;

  double _shippingFee = 0.0;
  final Set<String> _autoGiftExtras = {};

  late OrderWizardData _wizardData;

  double get _totalPrice => _items.where((i) => !i.isGift).fold(0, (sum, i) {
    final rutTien = i.attributes['rut_tien']?.toString() == 'true';
    final cashFee = rutTien
        ? (double.tryParse(i.attributes['cash_fee']?.toString() ?? '') ?? 0)
        : 0.0;
    return sum + i.unitPrice * i.quantity + cashFee;
  });

  double get _displayTotal => _totalPrice + _shippingFee;

  @override
  void initState() {
    super.initState();
    _dueDate = DateTime.now();
    _wizardData = OrderWizardData();
    final draft = ref.read(orderDraftProvider);
    if (draft != null) {
      _wizardData.customerName = draft.customerName;
      _wizardData.customerPhone = draft.customerPhone;
      _items.addAll(draft.items);
      _dueDate = draft.dueDate ?? DateTime.now();
      _dueTime = draft.dueTime;
      _wizardData.deliveryType = draft.deliveryType;
      _wizardData.deliveryAddress = draft.deliveryAddress;
      _notesCtrl.text = draft.notes;
      _depositEnabled = draft.depositEnabled;
      _depositAmountCtrl.text = draft.depositAmount;
      _depositMethod = draft.depositMethod;
      _source = draft.source;
    }
  }

  @override
  void deactivate() {
    _saveDraft();
    super.deactivate();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _depositAmountCtrl.dispose();
    super.dispose();
  }

  void _saveDraft() {
    if (_submitted) return;
    final draft = OrderDraft(
      customerName: _wizardData.customerName,
      customerPhone: _wizardData.customerPhone,
      items: List.of(_items),
      dueDate: _dueDate,
      dueTime: _dueTime,
      deliveryType: _wizardData.deliveryType,
      deliveryAddress: _wizardData.deliveryAddress,
      notes: _notesCtrl.text,
      depositEnabled: _depositEnabled,
      depositAmount: _depositAmountCtrl.text,
      depositMethod: _depositMethod,
      source: _source,
    );
    if (draft.isNotEmpty) {
      ref.read(orderDraftProvider.notifier).save(draft);
    } else {
      ref.read(orderDraftProvider.notifier).clear();
    }
  }

  String _formatTime(TimeOfDay t) => formatHourMinute(t.hour, t.minute);

  String _deriveSlot(TimeOfDay t) {
    if (t.hour < 12) return VN.timeSlotMorning;
    if (t.hour < 17) return VN.timeSlotAfternoon;
    return VN.timeSlotEvening;
  }

  void _checkAutoGift() {
    double qualifiedTotal = 0;
    for (final item in _items) {
      if (item.product.attributes['tang_kem']?.toString() == 'true' &&
          !item.isExtra) {
        qualifiedTotal += item.unitPrice * item.quantity;
      }
    }

    final giftThreshold = _giftThresholdFromConfig();
    final giftExtras = _giftExtrasFromConfig();
    if (qualifiedTotal >= giftThreshold) {
      for (final (name, price) in giftExtras) {
        if (!_autoGiftExtras.contains(name)) {
          _autoGiftExtras.add(name);
          _items.add(createExtraItem(name, price, isGift: true));
        }
      }
    }
  }

  double _giftThresholdFromConfig() {
    final thresholdAsync = ref.read(giftThresholdProvider);
    return thresholdAsync.when(
      data: (values) {
        for (final value in values) {
          final parsed = double.tryParse(value.trim());
          if (parsed != null && parsed > 0) return parsed;
        }
        return GiftConfig.giftThreshold;
      },
      loading: () => GiftConfig.giftThreshold,
      error: (_, _) => GiftConfig.giftThreshold,
    );
  }

  List<(String, double)> _giftExtrasFromConfig() {
    final extrasAsync = ref.read(giftExtrasProvider);
    return extrasAsync.when(
      data: (values) {
        final parsedExtras = <(String, double)>[];
        for (final value in values) {
          final parts = value.split('|');
          if (parts.length != 2) continue;
          final name = parts[0].trim();
          final price = double.tryParse(parts[1].trim());
          if (name.isNotEmpty && price != null && price >= 0) {
            parsedExtras.add((name, price));
          }
        }
        return parsedExtras.isEmpty ? GiftConfig.giftExtras : parsedExtras;
      },
      loading: () => GiftConfig.giftExtras,
      error: (_, _) => GiftConfig.giftExtras,
    );
  }

  void _addCatalogExtra(
    Product product, {
    int? priceChipId,
    double? customUnitPrice,
    bool isGift = false,
  }) {
    setState(() {
      final normalizedUnitPrice = customUnitPrice ?? product.basePrice;
      final existing = _items
          .where(
            (i) =>
                i.isExtra &&
                i.product.id == product.id &&
                i.isGift == isGift &&
                i.unitPrice == normalizedUnitPrice,
          )
          .firstOrNull;
      if (existing != null) {
        existing.quantity += 1;
        return;
      }

      _items.add(
        createCatalogExtraItem(
          product: product,
          isGift: isGift,
          priceChipId: priceChipId,
          customUnitPrice: customUnitPrice,
        ),
      );
    });
  }

  void _decrementExtra(DraftOrderItem item) {
    setState(() {
      if (item.quantity > 1) {
        item.quantity -= 1;
      } else {
        _items.remove(item);
        if (item.isGift) _autoGiftExtras.remove(item.product.name);
      }
    });
  }

  void _removeExtraItem(DraftOrderItem item) {
    setState(() {
      _items.remove(item);
      if (item.isGift) _autoGiftExtras.remove(item.product.name);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickHour() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => HourPickerDialog(initialHour: _dueTime?.hour ?? 8),
    );
    if (picked != null) {
      setState(() => _dueTime = TimeOfDay(hour: picked, minute: 0));
    }
  }

  Future<void> _openProductPicker() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ProductPickerPage(
          selectedItems: _items,
          onChanged: () => setState(() {}),
        ),
      ),
    );
    setState(_checkAutoGift);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      showTopSnackBar(context, 'Vui lòng chọn ít nhất một sản phẩm');
      return;
    }

    setState(() => _submitting = true);
    try {
      final service = ref.read(orderServiceProvider);

      final staffName = ref.read(loggedByProvider);
      final customerName = _wizardData.customerName.isEmpty
          ? 'Khách'
          : _wizardData.customerName;
      final newOrder = await service.createOrder(
        customerName: customerName,
        customerPhone: _wizardData.customerPhone,
        customerId: _wizardData.selectedCustomer?.id,
        items: _items.map((i) {
          final m = <String, dynamic>{
            'productId': i.product.id.toString(),
            'productName': i.product.name,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'notes': i.notes,
            'isBirthday': i.isBirthday,
            'isExtra': i.isExtra,
            'isGift': i.isGift,
            'attributes': i.attributes,
            'priceChipId': i.priceChipId,
          };
          if (i.isBirthday && i.age.isNotEmpty) {
            final age = int.tryParse(i.age.trim());
            if (age != null) m['age'] = age;
          }
          return m;
        }).toList(),
        shippingFee: _wizardData.shippingFee,
        dueDate: _dueDate != null ? formatApiDate(_dueDate!) : null,
        dueTime: _dueTime != null ? _formatTime(_dueTime!) : null,
        deliveryType: _wizardData.deliveryType,
        deliveryAddress: _wizardData.deliveryAddress,
        notes: _notesCtrl.text.trim(),
        source: _source.isEmpty ? null : _source,
        createdBy: staffName,
      );

      final hasPerItemPhotos = _items.any((i) => i.pendingPhotos.isNotEmpty);
      if (hasPerItemPhotos) {
        final workItemSvc = ref.read(workItemServiceProvider);
        final workItems = await workItemSvc.listWorkItems(newOrder.orderRef);
        workItems.sort((a, b) => a.position.compareTo(b.position));

        int totalPhotos = 0;
        int failedPhotos = 0;
        for (var idx = 0; idx < _items.length; idx++) {
          final draftItem = _items[idx];
          if (draftItem.pendingPhotos.isEmpty) continue;
          final workItemId = idx < workItems.length
              ? int.tryParse(workItems[idx].id)
              : null;
          for (final xfile in draftItem.pendingPhotos) {
            totalPhotos++;
            try {
              await service.uploadOrderPhoto(
                newOrder.orderRef,
                xfile,
                workItemId: workItemId,
              );
            } catch (e) {
              failedPhotos++;
              debugPrint('Photo upload failed (${xfile.path}): $e');
            }
          }
        }
        if (failedPhotos > 0 && mounted) {
          showTopSnackBar(
            context,
            'Tải lên ảnh: ${totalPhotos - failedPhotos}/$totalPhotos thành công, $failedPhotos lỗi',
          );
        }
      }

      if (_depositEnabled) {
        final rawAmount = double.tryParse(_depositAmountCtrl.text.trim());
        final amount = rawAmount != null ? vndFromThousands(rawAmount) : null;
        if (amount != null && amount > 0) {
          final txnService = ref.read(paymentTransactionServiceProvider);
          await txnService.createTransaction(
            newOrder.orderRef,
            amount: amount,
            type: 'deposit',
            method: _depositMethod,
          );
        }
      }

      for (final item in _items) {
        if (item.daDuaTienRut &&
            item.attributes['rut_tien']?.toString() == 'true') {
          final cashAmount = double.tryParse(
            item.attributes['cash_amount']?.toString() ?? '',
          );
          if (cashAmount != null && cashAmount > 0) {
            final txnService = ref.read(paymentTransactionServiceProvider);
            await txnService.createTransaction(
              newOrder.orderRef,
              amount: cashAmount,
              type: 'tien_rut',
              method: 'cash',
            );
          }
        }
      }

      await ref.read(orderListProvider.notifier).refresh();

      if (mounted) {
        _submitted = true;
        ref.read(orderDraftProvider.notifier).clear();
        showTopSnackBar(context, VN.orderCreated);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourcesAsync = ref.watch(orderSourcesProvider);
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
        title: const Text(VN.createOrder),
        actions: const [AppBarOverflowMenu()],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            _buildSourceSection(sourcesAsync),
            const SizedBox(height: 12),
            _buildCreatedBySection(),
            const SizedBox(height: 20),
            _buildProductsSection(theme),
            const SizedBox(height: 20),
            _buildExtrasSection(),
            const SizedBox(height: 20),
            _buildScheduleSection(),
            const SizedBox(height: 20),
            _buildWizardSection(shippingBusDefault, shippingDoorDefault),
            const SizedBox(height: 20),
            _buildDepositSection(),
            const SizedBox(height: 16),
            _buildSubmitButton(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceSection(AsyncValue<List<String>> sourcesAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(VN.orderSource),
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
                          _wizardData.customerName.isEmpty) {
                        _wizardData.customerName = VN.walkInCustomer;
                      } else if (wasSelected &&
                          s == VN.sourceTaiTiem &&
                          _wizardData.customerName == VN.walkInCustomer) {
                        _wizardData.customerName = '';
                      }
                    }),
                  ),
                )
                .toList(),
          ),
          loading: () => const SizedBox.shrink(),
          error: (e, st) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildCreatedBySection() {
    final staffName = ref.watch(loggedByProvider);
    if (staffName.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.person, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            '${VN.createdBy}: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          Text(
            staffName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(VN.products),
        if (_items.where((i) => !i.isExtra).isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Chưa chọn sản phẩm',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          ..._items
              .where((i) => !i.isExtra)
              .map(
                (item) => ExpandableItemCard(
                  key: ValueKey(item),
                  item: item,
                  onRemove: () => setState(() => _items.remove(item)),
                  onQtyChanged: (q) => setState(() {
                    item.quantity = q;
                    _checkAutoGift();
                  }),
                  onStateChanged: () => setState(() {}),
                ),
              ),
        OutlinedButton.icon(
          onPressed: _openProductPicker,
          icon: const Icon(Icons.add),
          label: const Text(VN.addProduct),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('${VN.total}: ', style: theme.textTheme.bodyMedium),
              Text(
                formatVND(_displayTotal),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (_wizardData.shippingFee > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '(${VN.shippingFee}: ${formatVND(_wizardData.shippingFee)})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildExtrasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(VN.extras),
        ..._items
            .where((i) => i.isExtra)
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.isGift
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.product.name} (${formatVND(item.unitPrice)})',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => _decrementExtra(item),
                    ),
                    Text(
                      '${item.quantity}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => setState(() => item.quantity += 1),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => _removeExtraItem(item),
                    ),
                  ],
                ),
              ),
            ),
        _ExtrasSection(onExtraAdded: _addCatalogExtra),
      ],
    );
  }

  Widget _buildScheduleSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(VN.dueDate),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(
            _dueDate != null ? formatDisplayDate(_dueDate) : VN.dueDate,
          ),
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        const SizedBox(height: 12),
        HourPresetChips(
          selectedTime: _dueTime,
          onSelected: (t) => setState(() => _dueTime = t),
        ),
        if (_dueTime != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickHour,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_dueTime!.hour}:00',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(_deriveSlot(_dueTime!)),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.primaryContainer,
              labelStyle: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWizardSection(double shippingBusDefault, double shippingDoorDefault) {
    return OrderWizard(
      data: _wizardData,
      onDataChanged: () => setState(() {}),
      onFinalize: _submit,
      showCustomerStep: true,
      showDeliveryStep: true,
      showReviewStep: true,
      skipCustomerIfWalkIn: false,
      skipDeliveryIfPickup: true,
      shippingBusDefault: shippingBusDefault,
      shippingDoorDefault: shippingDoorDefault,
      isProcessing: _submitting,
      extraReviewWidgets: [
        _buildReviewProductsSection(),
        _buildReviewScheduleSection(),
        if (_depositEnabled) _buildReviewDepositSection(),
      ],
    );
  }

  Widget _buildReviewProductsSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const SectionHeader(VN.products),
        ..._items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.product.name} x${item.quantity}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  formatVND(item.unitPrice * item.quantity),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('${VN.total}: ', style: theme.textTheme.bodyMedium),
            Text(
              formatVND(_displayTotal),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const SectionHeader(VN.dueDate),
        Text(
          _dueDate != null ? formatDisplayDate(_dueDate) : VN.dueDate,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (_dueTime != null) ...[
          const SizedBox(height: 4),
          Text(
            '${_dueTime!.hour}:00 (${_deriveSlot(_dueTime!)})',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  Widget _buildReviewDepositSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const SectionHeader(VN.depositSection),
        Text(
          '${formatVND(vndFromThousands(double.tryParse(_depositAmountCtrl.text.trim()) ?? 0))} (${_depositMethod == 'cash' ? VN.methodCash : VN.methodTransfer})',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildDepositSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: _depositEnabled,
          onChanged: (v) => setState(() => _depositEnabled = v ?? false),
          title: const Text(VN.depositSection),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        if (_depositEnabled) ...[
          TextFormField(
            controller: _depositAmountCtrl,
            decoration: const InputDecoration(
              labelText: VN.depositAmount,
              border: OutlineInputBorder(),
              suffixText: ',000đ',
              helperText: VN.paymentThousandsHint,
            ),
            keyboardType: TextInputType.number,
            validator: (v) {
              if (!_depositEnabled) return null;
              if (v == null || v.trim().isEmpty) return VN.fieldRequired;
              final amount = double.tryParse(v.trim());
              if (amount == null || amount <= 0) return VN.invalidPrice;
              return null;
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text(VN.methodCash),
                selected: _depositMethod == 'cash',
                onSelected: (_) => setState(() => _depositMethod = 'cash'),
              ),
              ChoiceChip(
                label: const Text(VN.methodTransfer),
                selected: _depositMethod == 'transfer',
                onSelected: (_) => setState(() => _depositMethod = 'transfer'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSubmitButton() {
    return FilledButton(
      onPressed: _submitting ? null : _submit,
      child: _submitting
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text(VN.submitOrder),
    );
  }
}

class _ExtrasSection extends ConsumerWidget {
  const _ExtrasSection({required this.onExtraAdded});

  final void Function(
    Product product, {
    int? priceChipId,
    double? customUnitPrice,
    bool isGift,
  }) onExtraAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extrasAsync = ref.watch(phuKienProductsProvider);
    final theme = Theme.of(context);

    return extrasAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (products) {
        if (products.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              VN.noConfiguredExtras,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: products.map((product) {
            return ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: Text('${product.name} (${formatVND(product.basePrice)})'),
              onPressed: () async {
                final selection = await showDialog<_CatalogExtraSelection>(
                  context: context,
                  builder: (_) => _CatalogExtraPriceDialog(product: product),
                );
                if (selection == null) return;
                onExtraAdded(
                  product,
                  priceChipId: selection.priceChipId,
                  customUnitPrice: selection.customUnitPrice,
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}

class _CatalogExtraSelection {
  const _CatalogExtraSelection({this.priceChipId, this.customUnitPrice});

  final int? priceChipId;
  final double? customUnitPrice;
}

class _CatalogExtraPriceDialog extends StatefulWidget {
  const _CatalogExtraPriceDialog({required this.product});

  final Product product;

  @override
  State<_CatalogExtraPriceDialog> createState() => _CatalogExtraPriceDialogState();
}

class _CatalogExtraPriceDialogState extends State<_CatalogExtraPriceDialog> {
  static const int _manualOptionId = -999;
  final TextEditingController _manualCtrl = TextEditingController();
  late int _selectedOptionId;

  @override
  void initState() {
    super.initState();
    _selectedOptionId = 0;
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = <(int id, String label, double price, int? chipId)>[
      (0, VN.giaCoSo, widget.product.basePrice, null),
      ...widget.product.priceChips.map(
        (chip) => (chip.id, chip.label, chip.price, chip.id),
      ),
      (_manualOptionId, VN.donGiaNhapTay, widget.product.basePrice, null),
    ];

    return AlertDialog(
      title: Text(widget.product.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) {
              final selected = _selectedOptionId == option.$1;
              return ChoiceChip(
                label: Text('${option.$2} (${formatVND(option.$3)})'),
                selected: selected,
                onSelected: (_) => setState(() => _selectedOptionId = option.$1),
              );
            }).toList(),
          ),
          if (_selectedOptionId == _manualOptionId) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _manualCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: VN.itemPrice,
                suffixText: 'đ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(VN.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_selectedOptionId == _manualOptionId) {
              final manualPrice = double.tryParse(_manualCtrl.text.trim());
              if (manualPrice == null || manualPrice < 0) {
                showTopSnackBar(context, VN.invalidPrice);
                return;
              }
              Navigator.pop(
                context,
                _CatalogExtraSelection(customUnitPrice: manualPrice),
              );
              return;
            }

            final selected = options.firstWhere((o) => o.$1 == _selectedOptionId);
            if (selected.$4 == null) {
              Navigator.pop(
                context,
                const _CatalogExtraSelection(customUnitPrice: null),
              );
            } else {
              Navigator.pop(
                context,
                _CatalogExtraSelection(priceChipId: selected.$4),
              );
            }
          },
          child: const Text(VN.xacNhan),
        ),
      ],
    );
  }
}
