import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import '../../../../data/models/product.dart';
import '../../../../data/models/work_item.dart';
import '../../../../providers/order_providers.dart';
import '../../../../providers/products_provider.dart';
import '../../../../shared/utils/api_error.dart';
import '../../../../shared/widgets/vietnamese_labels.dart';
import '../../utils/trung_bay_inventory_extensions.dart';
import '../../widgets/order_photo_section.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class WorkItemEditCard extends ConsumerStatefulWidget {
  const WorkItemEditCard({super.key, required this.orderRef, required this.item});

  final String orderRef;
  final WorkItem item;

  @override
  ConsumerState<WorkItemEditCard> createState() => _WorkItemEditCardState();
}

class _WorkItemEditCardState extends ConsumerState<WorkItemEditCard> {
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

  List<Widget> _buildEnumChipSections(ThemeData theme, Product? product) {
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
    final product = _findProduct();
    final isTrungBay = product.isTrungBay;
    final useInventory = item.attributes.useInventory;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
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
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: item.quantity > 1
                      ? () => _editItem(quantity: item.quantity - 1)
                      : null,
                ),
                Text('${item.quantity}', style: theme.textTheme.bodyMedium),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _editItem(quantity: item.quantity + 1),
                ),
                if (item.isExtra) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: VN.giftToggleTooltip,
                    child: InkWell(
                      onTap: _toggleGift,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: item.isGift
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: item.isGift ? Colors.green : Colors.grey.shade300,
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
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20),
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
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  if (isTrungBay) ...[
                    SwitchListTile.adaptive(
                      value: useInventory,
                      onChanged: (value) {
                        final next = Map<String, dynamic>.from(widget.item.attributes);
                        next['useInventory'] = value ? 'true' : 'false';
                        _editItem(attributes: next);
                      },
                      title: const Text(VN.useInventory),
                      subtitle: useInventory ? Text(product.stockInlineText) : null,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                  ..._buildEnumChipSections(theme, product),
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
                          _savedCashAmount = _cashAmountCtrl.text.trim();
                          _savedCashFee = _cashFeeCtrl.text.trim();
                          _cashAmountCtrl.clear();
                          _cashFeeCtrl.clear();
                          _editItem(attributes: {});
                        } else {
                          if (_savedCashAmount.isNotEmpty) _cashAmountCtrl.text = _savedCashAmount;
                          if (_savedCashFee.isNotEmpty) _cashFeeCtrl.text = _savedCashFee;
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
                      title: const Text(VN.rutTien),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    if (_rutTien) ...[
                      Row(
                        children: [
                          const Text('${VN.soTienRut}: '),
                          IconButton.filled(
                            onPressed: () {
                              final current = int.tryParse(_cashAmountCtrl.text) ?? 0;
                              if (current > _minCashAmount) {
                                final next = current - _cashAmountStep;
                                final clamped = next < _minCashAmount ? _minCashAmount : next;
                                setState(() {
                                  _cashAmountCtrl.text = '$clamped';
                                  _editingCashAmount = false;
                                });
                                _saveCashAttributes();
                              }
                            },
                            icon: const Icon(Icons.remove, size: 16),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _editingCashAmount = true),
                              child: _editingCashAmount
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: TextFormField(
                                        controller: _cashAmountCtrl,
                                        autofocus: true,
                                        textAlign: TextAlign.center,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          suffixText: 'đ',
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(9),
                                        ],
                                        onChanged: (_) => _saveCashAttributes(),
                                        onEditingComplete: () {
                                          final val = int.tryParse(_cashAmountCtrl.text) ?? 0;
                                          if (val < _minCashAmount && val != 0) {
                                            _cashAmountCtrl.text = '$_minCashAmount';
                                          }
                                          _saveCashAttributes();
                                          setState(() => _editingCashAmount = false);
                                        },
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        _cashAmountCtrl.text.isEmpty || _cashAmountCtrl.text == '0'
                                            ? '0đ'
                                            : formatVND((int.tryParse(_cashAmountCtrl.text) ?? 0).toDouble()),
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                    ),
                            ),
                          ),
                          IconButton.filled(
                            onPressed: () {
                              final current = int.tryParse(_cashAmountCtrl.text) ?? 0;
                              final next = current + _cashAmountStep;
                              final clamped = next < _minCashAmount ? _minCashAmount : next;
                              setState(() {
                                _cashAmountCtrl.text = '$clamped';
                                _editingCashAmount = false;
                              });
                              _saveCashAttributes();
                            },
                            icon: const Icon(Icons.add, size: 16),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('${VN.phiRutTien}: '),
                          IconButton.filled(
                            onPressed: () {
                              final current = int.tryParse(_cashFeeCtrl.text) ?? 0;
                              if (current >= _cashFeeStep) {
                                _cashFeeCtrl.text = '${current - _cashFeeStep}';
                                _saveCashAttributes();
                              }
                            },
                            icon: const Icon(Icons.remove, size: 16),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              formatVND((int.tryParse(_cashFeeCtrl.text) ?? _defaultCashFee).toDouble()),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton.filled(
                            onPressed: () {
                              final current = int.tryParse(_cashFeeCtrl.text) ?? _defaultCashFee;
                              _cashFeeCtrl.text = '${current + _cashFeeStep}';
                              _saveCashAttributes();
                            },
                            icon: const Icon(Icons.add, size: 16),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
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
