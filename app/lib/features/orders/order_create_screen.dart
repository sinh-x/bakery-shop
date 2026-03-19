import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/api/order_service.dart';
import '../../data/models/product.dart';
import '../../providers/order_providers.dart';
import '../../providers/products_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

// Holds a product and its selected quantity for the order
class _SelectedItem {
  final Product product;
  int quantity = 1;
  _SelectedItem({required this.product});
}

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
  final _ageCtrl = TextEditingController();

  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  String _deliveryType = 'pickup';
  bool _isBirthday = false;

  final List<_SelectedItem> _items = [];
  bool _submitting = false;

  bool get _needsAddress =>
      _deliveryType == 'bus' || _deliveryType == 'door';

  double get _totalPrice =>
      _items.fold(0, (sum, i) => sum + i.product.basePrice * i.quantity);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
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

  Future<void> _openProductPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductPickerSheet(
        selectedItems: _items,
        onChanged: () => setState(() {}),
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

      final notesParts = <String>[];
      if (_isBirthday) {
        final age = _ageCtrl.text.trim();
        notesParts.add(
          age.isNotEmpty ? '[${VN.isBirthday} - $age tuổi]' : '[${VN.isBirthday}]',
        );
      }
      final userNotes = _notesCtrl.text.trim();
      if (userNotes.isNotEmpty) notesParts.add(userNotes);

      await service.createOrder(
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim(),
        items: _items
            .map(
              (i) => {
                'productId': i.product.id.toString(),
                'productName': i.product.name,
                'quantity': i.quantity,
                'unitPrice': i.product.basePrice,
              },
            )
            .toList(),
        dueDate: _dueDate != null ? _formatDateApi(_dueDate!) : null,
        dueTime: _dueTime != null ? _formatTime(_dueTime!) : null,
        deliveryType: _deliveryType,
        deliveryAddress: _addressCtrl.text.trim(),
        notes: notesParts.join(' '),
      );

      await ref.read(orderListProvider.notifier).refresh();

      if (mounted) {
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
                (item) => _SelectedItemTile(
                  item: item,
                  onRemove: () => setState(() => _items.remove(item)),
                  onQtyChanged: (q) => setState(() => item.quantity = q),
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

            // ── Options ───────────────────────────────────────────────
            CheckboxListTile(
              value: _isBirthday,
              onChanged: (v) => setState(() => _isBirthday = v ?? false),
              title: const Text(VN.isBirthday),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (_isBirthday) ...[
              TextFormField(
                controller: _ageCtrl,
                decoration: const InputDecoration(
                  labelText: VN.birthdayAge,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
            ],

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

// ── Selected item tile ────────────────────────────────────────────────────────

class _SelectedItemTile extends StatelessWidget {
  const _SelectedItemTile({
    required this.item,
    required this.onRemove,
    required this.onQtyChanged,
  });

  final _SelectedItem item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQtyChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = categoryEmojiMap[item.product.category] ?? '🍰';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
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
                    item.product.name,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    formatVND(item.product.basePrice),
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
              onPressed: item.quantity > 1
                  ? () => onQtyChanged(item.quantity - 1)
                  : onRemove,
            ),
            SizedBox(
              width: 24,
              child: Text(
                '${item.quantity}',
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              iconSize: 20,
              onPressed: () => onQtyChanged(item.quantity + 1),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: theme.colorScheme.error,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Product picker bottom sheet ───────────────────────────────────────────────

class _ProductPickerSheet extends ConsumerStatefulWidget {
  const _ProductPickerSheet({
    required this.selectedItems,
    required this.onChanged,
  });

  final List<_SelectedItem> selectedItems;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<_ProductPickerSheet> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _getQty(Product product) {
    return widget.selectedItems
            .where((i) => i.product.id == product.id)
            .firstOrNull
            ?.quantity ??
        0;
  }

  void _increment(Product product) {
    final existing = widget.selectedItems
        .where((i) => i.product.id == product.id)
        .firstOrNull;
    if (existing != null) {
      existing.quantity++;
    } else {
      widget.selectedItems.add(_SelectedItem(product: product));
    }
    setState(() {});
    widget.onChanged();
  }

  void _decrement(Product product) {
    final existing = widget.selectedItems
        .where((i) => i.product.id == product.id)
        .firstOrNull;
    if (existing == null) return;
    if (existing.quantity <= 1) {
      widget.selectedItems.remove(existing);
    } else {
      existing.quantity--;
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        // Handle
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  VN.selectProducts,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: VN.searchProducts,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        // Product list
        Expanded(
          child: productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(VN.apiError)),
            data: (products) {
              final active = products.where((p) => p.active == 1).toList();
              final filtered = _search.isEmpty
                  ? active
                  : active
                      .where(
                        (p) =>
                            p.name
                                .toLowerCase()
                                .contains(_search.toLowerCase()) ||
                            p.productCode
                                .toLowerCase()
                                .contains(_search.toLowerCase()),
                      )
                      .toList();

              if (filtered.isEmpty) {
                return Center(child: Text(VN.noProducts));
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, index) {
                  final product = filtered[index];
                  final qty = _getQty(product);
                  final emoji = categoryEmojiMap[product.category] ?? '🍰';

                  return ListTile(
                    leading: Text(
                      emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                    title: Text(product.name),
                    subtitle: Text(formatVND(product.basePrice)),
                    trailing: qty == 0
                        ? IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _increment(product),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                iconSize: 20,
                                onPressed: () => _decrement(product),
                              ),
                              Text(
                                '$qty',
                                style: theme.textTheme.titleSmall,
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                iconSize: 20,
                                onPressed: () => _increment(product),
                              ),
                            ],
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
