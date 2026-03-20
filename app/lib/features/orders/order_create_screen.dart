import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../data/api/api_client.dart';
import '../../data/api/order_service.dart';
import '../../data/api/payment_transaction_service.dart';
import '../../data/api/work_item_service.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../providers/categories_provider.dart';
import '../../providers/order_providers.dart';
import '../../providers/products_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import '../products/widgets/product_card.dart';
import 'widgets/order_photo_section.dart';

class OrderCreateScreen extends ConsumerStatefulWidget {
  const OrderCreateScreen({super.key});

  @override
  ConsumerState<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends ConsumerState<OrderCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _deliveryType = 'pickup';

  bool _depositEnabled = false;
  final _depositAmountCtrl = TextEditingController();
  String _depositMethod = 'cash';

  final List<DraftOrderItem> _items = [];
  final List<DraftPendingPhoto> _pendingPhotos = [];
  final _picker = ImagePicker();
  bool _submitting = false;
  bool _submitted = false;

  bool get _needsAddress =>
      _deliveryType == 'bus' || _deliveryType == 'door';

  double get _totalPrice =>
      _items.fold(0, (sum, i) => sum + i.unitPrice * i.quantity);

  @override
  void initState() {
    super.initState();
    final draft = ref.read(orderDraftProvider);
    if (draft != null) {
      _nameCtrl.text = draft.customerName;
      _phoneCtrl.text = draft.customerPhone;
      _items.addAll(draft.items);
      _dueDate = draft.dueDate;
      _dueTime = draft.dueTime;
      _deliveryType = draft.deliveryType;
      _addressCtrl.text = draft.deliveryAddress;
      _notesCtrl.text = draft.notes;
      _depositEnabled = draft.depositEnabled;
      _depositAmountCtrl.text = draft.depositAmount;
      _depositMethod = draft.depositMethod;
      _pendingPhotos.addAll(draft.pendingPhotos);
    }
  }

  @override
  void dispose() {
    _saveDraft();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _depositAmountCtrl.dispose();
    super.dispose();
  }

  void _saveDraft() {
    if (_submitted) return;
    final draft = OrderDraft(
      customerName: _nameCtrl.text,
      customerPhone: _phoneCtrl.text,
      items: List.of(_items),
      dueDate: _dueDate,
      dueTime: _dueTime,
      deliveryType: _deliveryType,
      deliveryAddress: _addressCtrl.text,
      notes: _notesCtrl.text,
      depositEnabled: _depositEnabled,
      depositAmount: _depositAmountCtrl.text,
      depositMethod: _depositMethod,
      pendingPhotos: List.of(_pendingPhotos),
    );
    if (draft.isNotEmpty) {
      ref.read(orderDraftProvider.notifier).save(draft);
    } else {
      ref.read(orderDraftProvider.notifier).clear();
    }
  }

  String _formatDateApi(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _formatDateDisplay(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _deriveSlot(TimeOfDay t) {
    if (t.hour < 12) return VN.timeSlotMorning;
    if (t.hour < 17) return VN.timeSlotAfternoon;
    return VN.timeSlotEvening;
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
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _dueTime = picked);
  }

  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;
    setState(() {
      for (final f in files) {
        _pendingPhotos.add(DraftPendingPhoto(file: File(f.path)));
      }
    });
  }

  Future<void> _editPendingTags(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PendingTagEditSheet(
        initialTags: _pendingPhotos[index].tags,
        onSaved: (tags) => setState(() => _pendingPhotos[index].tags = tags),
      ),
    );
  }

  Future<void> _openProductPicker() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ProductPickerPage(
          selectedItems: _items,
          onChanged: () => setState(() {}),
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất một sản phẩm')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final service = ref.read(orderServiceProvider);

      final newOrder = await service.createOrder(
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim(),
        items: _items.map((i) {
          final m = <String, dynamic>{
            'productId': i.product.id.toString(),
            'productName': i.product.name,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'notes': i.notes,
            'isBirthday': i.isBirthday,
          };
          if (i.isBirthday && i.age.isNotEmpty) {
            final age = int.tryParse(i.age.trim());
            if (age != null) m['age'] = age;
          }
          return m;
        }).toList(),
        dueDate: _dueDate != null ? _formatDateApi(_dueDate!) : null,
        dueTime: _dueTime != null ? _formatTime(_dueTime!) : null,
        deliveryType: _deliveryType,
        deliveryAddress: _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );

      // Upload photos (per-item + order-level)
      final hasPerItemPhotos = _items.any((i) => i.pendingPhotoPaths.isNotEmpty);
      if (hasPerItemPhotos || _pendingPhotos.isNotEmpty) {
        final workItemSvc = ref.read(workItemServiceProvider);
        final workItems = await workItemSvc.listWorkItems(newOrder.orderRef);
        workItems.sort((a, b) => a.position.compareTo(b.position));

        // Per-item photos mapped by position index
        for (var idx = 0; idx < _items.length; idx++) {
          final draftItem = _items[idx];
          if (draftItem.pendingPhotoPaths.isEmpty) continue;
          final workItemId = idx < workItems.length
              ? int.tryParse(workItems[idx].id)
              : null;
          for (final path in draftItem.pendingPhotoPaths) {
            await service.uploadOrderPhoto(
              newOrder.orderRef,
              File(path),
              workItemId: workItemId,
            );
          }
        }

        // Order-level photos (no workItemId)
        for (final pending in _pendingPhotos) {
          await service.uploadOrderPhoto(
            newOrder.orderRef,
            pending.file,
            tags: pending.tags.join(','),
          );
        }
      }

      // Record initial deposit if provided
      if (_depositEnabled) {
        final rawAmount = double.tryParse(_depositAmountCtrl.text.trim());
        // Multiply by 1000: staff types 200 → actual amount 200,000
        final amount = rawAmount != null ? rawAmount * 1000 : null;
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

      await ref.read(orderListProvider.notifier).refresh();

      if (mounted) {
        _submitted = true;
        ref.read(orderDraftProvider.notifier).clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VN.orderCreated)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${VN.apiError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(VN.createOrder)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            // ── Customer ──────────────────────────────────────────────
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
              validator: (v) {
                if (_needsAddress && (v == null || v.trim().isEmpty)) {
                  return VN.fieldRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // ── Products ──────────────────────────────────────────────
            _SectionHeader(VN.products),
            if (_items.isEmpty)
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
              ..._items.map(
                (item) => _ExpandableItemCard(
                  key: ValueKey(item),
                  item: item,
                  onRemove: () => setState(() => _items.remove(item)),
                  onQtyChanged: (q) => setState(() => item.quantity = q),
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
                    formatVND(_totalPrice),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // ── Schedule ──────────────────────────────────────────────
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
                      _dueTime != null ? _formatTime(_dueTime!) : VN.dueTime,
                    ),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
              ],
            ),
            if (_dueTime != null) ...[
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
            const SizedBox(height: 20),

            // ── Delivery ──────────────────────────────────────────────
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
              onSelectionChanged: (s) =>
                  setState(() => _deliveryType = s.first),
            ),
            if (_needsAddress) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: VN.deliveryAddress,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _needsAddress && (v == null || v.trim().isEmpty)
                    ? VN.fieldRequired
                    : null,
              ),
            ],
            const SizedBox(height: 20),

            // ── Notes ─────────────────────────────────────────────────
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

            // ── Deposit ───────────────────────────────────────────────
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
                  helperText: 'Nhập nghìn đồng (VD: 200 = 200.000đ)',
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
                    onSelected: (_) =>
                        setState(() => _depositMethod = 'transfer'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // ── Photos ────────────────────────────────────────────────
            _SectionHeader(VN.pendingPhotosLabel),
            if (_pendingPhotos.isNotEmpty) ...[
              SizedBox(
                height: 134,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: _pendingPhotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, index) {
                    final pending = _pendingPhotos[index];
                    return SizedBox(
                      width: 90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  pending.file,
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              // Remove button
                              Positioned(
                                top: 4,
                                left: 4,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _pendingPhotos.removeAt(index),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                              // Tag edit button
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _editPendingTags(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.label_outline,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pending.tags.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 2,
                              runSpacing: 2,
                              children: pending.tags.map((key) {
                                final tagDef = kOrderPhotoTags
                                    .where((t) => t.key == key)
                                    .firstOrNull;
                                final color = tagDef?.color ?? Colors.grey;
                                final label = tagDef?.label ?? key;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(30),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: color.withAlpha(100),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _pickPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text(VN.addOrderPhoto),
            ),
            const SizedBox(height: 24),

            // ── Submit ────────────────────────────────────────────────
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(VN.submitOrder),
            ),
            const SizedBox(height: 16),
          ],
        ),
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

// ── Expandable item card ───────────────────────────────────────────────────────

class _ExpandableItemCard extends StatefulWidget {
  const _ExpandableItemCard({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onQtyChanged,
    required this.onStateChanged,
  });

  final DraftOrderItem item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onStateChanged;

  @override
  State<_ExpandableItemCard> createState() => _ExpandableItemCardState();
}

class _ExpandableItemCardState extends State<_ExpandableItemCard> {
  bool _expanded = true;
  bool _isBirthday = false;
  late TextEditingController _notesCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _priceCtrl;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _isBirthday = widget.item.isBirthday;
    _notesCtrl = TextEditingController(text: widget.item.notes);
    _ageCtrl = TextEditingController(text: widget.item.age);
    _priceCtrl = TextEditingController(
      text: widget.item.unitPrice.toInt().toString(),
    );
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _ageCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickItemPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;
    setState(() {
      for (final f in files) {
        widget.item.pendingPhotoPaths.add(f.path);
      }
    });
    widget.onStateChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = categoryEmojiMap[widget.item.product.category] ?? '🍰';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          // ── Header row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.product.name,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        formatVND(widget.item.unitPrice),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  iconSize: 20,
                  onPressed: widget.item.quantity > 1
                      ? () => widget.onQtyChanged(widget.item.quantity - 1)
                      : widget.onRemove,
                ),
                SizedBox(
                  width: 24,
                  child: Text(
                    '${widget.item.quantity}',
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  iconSize: 20,
                  onPressed: () =>
                      widget.onQtyChanged(widget.item.quantity + 1),
                ),
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
                  onPressed: widget.onRemove,
                ),
              ],
            ),
          ),

          // ── Expanded section ─────────────────────────────────────────
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
                    decoration: const InputDecoration(
                      labelText: VN.itemPrice,
                      border: OutlineInputBorder(),
                      suffixText: 'đ',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final price = double.tryParse(v.trim());
                      widget.item.customUnitPrice =
                          price ?? widget.item.product.basePrice;
                      widget.onStateChanged();
                    },
                  ),
                  const SizedBox(height: 8),
                  // Notes
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: VN.notes,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                    onChanged: (v) => widget.item.notes = v,
                  ),
                  const SizedBox(height: 4),
                  // Birthday checkbox
                  CheckboxListTile(
                    value: _isBirthday,
                    onChanged: (v) {
                      setState(() => _isBirthday = v ?? false);
                      widget.item.isBirthday = _isBirthday;
                    },
                    title: const Text(VN.isBirthday),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  if (_isBirthday) ...[
                    TextFormField(
                      controller: _ageCtrl,
                      decoration: const InputDecoration(
                        labelText: VN.birthdayAge,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => widget.item.age = v,
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Per-item photo thumbnails
                  if (widget.item.pendingPhotoPaths.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.item.pendingPhotoPaths.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (ctx, idx) {
                          final path = widget.item.pendingPhotoPaths[idx];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  File(path),
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                left: 2,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    widget.item.pendingPhotoPaths.removeAt(idx);
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  OutlinedButton.icon(
                    onPressed: _pickItemPhotos,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 16,
                    ),
                    label: const Text(VN.addOrderPhoto),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Pending photo tag editor ───────────────────────────────────────────────────

class _PendingTagEditSheet extends StatefulWidget {
  const _PendingTagEditSheet({
    required this.initialTags,
    required this.onSaved,
  });

  final Set<String> initialTags;
  final ValueChanged<Set<String>> onSaved;

  @override
  State<_PendingTagEditSheet> createState() => _PendingTagEditSheetState();
}

class _PendingTagEditSheetState extends State<_PendingTagEditSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialTags);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            VN.editPhotoTags,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kOrderPhotoTags.map((tag) {
              final selected = _selected.contains(tag.key);
              return FilterChip(
                label: Text(tag.label),
                selected: selected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selected.add(tag.key);
                    } else {
                      _selected.remove(tag.key);
                    }
                  });
                },
                selectedColor: tag.color.withAlpha(50),
                checkmarkColor: tag.color,
                side: BorderSide(
                  color: selected ? tag.color : Colors.grey.shade300,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              widget.onSaved(_selected);
              Navigator.pop(context);
            },
            child: const Text(VN.save),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Product picker full-screen page ──────────────────────────────────────────

class _ProductPickerPage extends ConsumerStatefulWidget {
  const _ProductPickerPage({
    required this.selectedItems,
    required this.onChanged,
  });

  final List<DraftOrderItem> selectedItems;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends ConsumerState<_ProductPickerPage> {
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds =
        widget.selectedItems.map((i) => i.product.id).toSet();
  }

  void _toggleProduct(Product product) {
    setState(() {
      if (_selectedIds.contains(product.id)) {
        _selectedIds.remove(product.id);
      } else {
        _selectedIds.add(product.id);
      }
    });
  }

  void _onConfirm(List<Product> allProducts) {
    // Remove items that were deselected
    widget.selectedItems
        .removeWhere((i) => !_selectedIds.contains(i.product.id));

    // Add newly selected products (quantity = 1)
    for (final id in _selectedIds) {
      final alreadyAdded =
          widget.selectedItems.any((i) => i.product.id == id);
      if (!alreadyAdded) {
        final product = allProducts.where((p) => p.id == id).firstOrNull;
        if (product != null) {
          widget.selectedItems.add(DraftOrderItem(product: product));
        }
      }
    }

    widget.onChanged();
    Navigator.of(context).pop();
  }

  Widget _buildGrid(
    List<Category> categories,
    List<Product> allProducts,
    String baseUrl,
  ) {
    final activeCategories =
        categories.where((c) => c.active == 1).toList();
    final activeProducts =
        allProducts.where((p) => p.active == 1).toList();

    final appBar = _buildAppBar(allProducts, activeCategories);

    if (activeCategories.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: _buildCategoryGrid(activeProducts, baseUrl),
      );
    }

    return DefaultTabController(
      length: activeCategories.length,
      child: Scaffold(
        appBar: appBar,
        body: TabBarView(
          children: activeCategories.map((cat) {
            final catProducts = activeProducts
                .where((p) => p.category == cat.slug)
                .toList();
            return catProducts.isEmpty
                ? Center(
                    child: Text(
                      VN.noProducts,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  )
                : _buildCategoryGrid(catProducts, baseUrl);
          }).toList(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    List<Product> allProducts,
    List<Category> activeCategories,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        _selectedIds.isEmpty
            ? VN.selectProducts
            : '${_selectedIds.length} đã chọn',
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.check),
          tooltip: 'Xác nhận',
          onPressed: () => _onConfirm(allProducts),
        ),
      ],
      bottom: activeCategories.isNotEmpty
          ? TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: activeCategories.map((cat) {
                final icon = cat.icon.isNotEmpty
                    ? cat.icon
                    : (categoryEmojiMap[cat.slug] ?? '');
                return Tab(text: '$icon ${cat.name}');
              }).toList(),
            )
          : null,
    );
  }

  Widget _buildCategoryGrid(List<Product> products, String baseUrl) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final product = products[i];
        final selected = _selectedIds.contains(product.id);
        return Stack(
          fit: StackFit.expand,
          children: [
            ProductCard(
              product: product,
              photoBaseUrl: baseUrl,
              onTap: () => _toggleProduct(product),
            ),
            if (selected)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(productsProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return productsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(VN.selectProducts),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(VN.selectProducts),
        ),
        body: Center(child: Text(VN.apiError)),
      ),
      data: (products) => categoriesAsync.when(
        loading: () => _buildGrid([], products, baseUrl),
        error: (e, _) => _buildGrid([], products, baseUrl),
        data: (categories) => _buildGrid(categories, products, baseUrl),
      ),
    );
  }
}
