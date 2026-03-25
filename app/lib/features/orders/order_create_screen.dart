import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/api/order_service.dart';
import '../../data/api/payment_transaction_service.dart';
import '../../data/api/work_item_service.dart';
import '../../providers/config_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/order_providers.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/expandable_item_card.dart';
import 'widgets/hour_picker.dart';
import 'widgets/product_picker_page.dart';

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
  String _source = '';

  bool _depositEnabled = false;
  final _depositAmountCtrl = TextEditingController();
  String _depositMethod = 'cash';

  final List<DraftOrderItem> _items = [];
  bool _submitting = false;
  bool _submitted = false;

  bool get _needsAddress =>
      _deliveryType == 'bus' || _deliveryType == 'door';

  bool get _needsNotes => _deliveryType != 'pickup';

  double get _totalPrice =>
      _items.fold(0, (sum, i) => sum + i.unitPrice * i.quantity);

  @override
  void initState() {
    super.initState();
    _dueDate = DateTime.now(); // F4: default to today
    final draft = ref.read(orderDraftProvider);
    if (draft != null) {
      _nameCtrl.text = draft.customerName;
      _phoneCtrl.text = draft.customerPhone;
      _items.addAll(draft.items);
      _dueDate = draft.dueDate ?? DateTime.now(); // F4: preserve draft or default today
      _dueTime = draft.dueTime;
      _deliveryType = draft.deliveryType;
      _addressCtrl.text = draft.deliveryAddress;
      _notesCtrl.text = draft.notes;
      _depositEnabled = draft.depositEnabled;
      _depositAmountCtrl.text = draft.depositAmount;
      _depositMethod = draft.depositMethod;
      _source = draft.source; // F1
    }
  }

  @override
  void deactivate() {
    _saveDraft();
    super.deactivate();
  }

  @override
  void dispose() {
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
      source: _source, // F1
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
      initialDate: _dueDate ?? DateTime.now(), // F4: starts at today
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  // F5: Hour picker (replaces showTimePicker)
  Future<void> _pickHour() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => HourPickerDialog(initialHour: _dueTime?.hour ?? 8),
    );
    if (picked != null) setState(() => _dueTime = TimeOfDay(hour: picked, minute: 0));
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
    setState(() {});
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
        source: _source.isEmpty ? null : _source, // F1
        createdBy: staffName,
      );

      // Upload per-item photos (F6: order-level photos removed from creation)
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
    final sourcesAsync = ref.watch(orderSourcesProvider); // F1

    return Scaffold(
      appBar: AppBar(title: const Text(VN.createOrder)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            // ── Source (F1) ───────────────────────────────────────────
            _SectionHeader(VN.orderSource),
            sourcesAsync.when(
              data: (sources) => Wrap(
                spacing: 8,
                runSpacing: 4,
                children: sources
                    .map((s) => ChoiceChip(
                          label: Text(s),
                          selected: _source == s,
                          onSelected: (_) => setState(() {
                            final wasSelected = _source == s;
                            _source = wasSelected ? '' : s;
                            if (!wasSelected && s == 'Tại Tiệm' && _nameCtrl.text.isEmpty) {
                              _nameCtrl.text = 'Khách Vãng Lai';
                            } else if (wasSelected && s == 'Tại Tiệm' && _nameCtrl.text == 'Khách Vãng Lai') {
                              _nameCtrl.text = '';
                            }
                          }),
                        ))
                    .toList(),
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),

            // ── Người tạo (auto-filled from settings) ─────────────────
            Builder(builder: (context) {
              final staffName = ref.watch(loggedByProvider);
              if (staffName.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('${VN.createdBy}: ',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey)),
                    Text(staffName,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w500)),
                  ],
                ),
              );
            }),

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
                (item) => ExpandableItemCard(
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

            // ── Schedule (F4 + F5) ────────────────────────────────────
            _SectionHeader(VN.dueDate),
            // F4: Date button (always shows date, defaults to today)
            OutlinedButton.icon(
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
            const SizedBox(height: 12),
            // F5: Time preset chips
            HourPresetChips(
              selectedTime: _dueTime,
              onSelected: (t) => setState(() => _dueTime = t),
            ),
            if (_dueTime != null) ...[
              const SizedBox(height: 8),
              // F5: Tappable hour label — opens hour picker
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

            // ── Notes (F3: only for non-pickup) ───────────────────────
            if (_needsNotes) ...[
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
            ],

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

