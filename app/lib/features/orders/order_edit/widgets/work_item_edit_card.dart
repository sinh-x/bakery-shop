import 'package:bakery_app/shared/utils.dart' show formatVND, showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import '../../../../data/models/product.dart';
import '../../../../data/models/work_item.dart';
import '../../../../providers/order_providers.dart';
import '../../../../data/providers/products_provider.dart';
import '../../../../shared/utils/api_error.dart';
import '../../utils/trung_bay_inventory_extensions.dart';
import '../../widgets/candle_type_radio_group.dart';
import '../../widgets/order_photo_section.dart';
import '../../widgets/product_picker_page.dart';
import 'package:bakery_app/shared/utils/chip_stock_display.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/labels/stock.dart';
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
  String? _candleType;
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

  // Trưng bày markup UI state (DG-342 Phase 1 — FR1/FR2/AC1).
  // Selling price is entered in thousands of đồng (",000đ" suffix); the floor
  // warning shows when the entered value falls below the assigned (COGS
  // anchor) price. On save the selling price is clamped to the assigned
  // price so a unitPrice < assignedPrice row is never persisted.
  String? _floorWarning;

  @override
  void initState() {
    super.initState();
    _isBirthday = widget.item.isBirthday;
    _notesCtrl = TextEditingController(text: widget.item.notes);
    _ageCtrl = TextEditingController(
      text: widget.item.age != null ? '${widget.item.age}' : '',
    );
    final isMarkup = _findProduct().isTrungBay;
    _priceCtrl = TextEditingController(
      text: isMarkup
          ? (widget.item.unitPrice / 1000).toInt().toString()
          : widget.item.unitPrice.toInt().toString(),
    );
    final cashAmount = widget.item.attributes['cash_amount']?.toString() ?? '';
    final cashFee = widget.item.attributes['cash_fee']?.toString() ?? '';
    _cashAmountCtrl = TextEditingController(text: cashAmount);
    _cashFeeCtrl = TextEditingController(
      text: cashFee.isNotEmpty ? cashFee : '$_defaultCashFee',
    );
    _rutTien = widget.item.attributes['rut_tien']?.toString() == 'true';
    // AC1/AC7: default candle type so the radio group renders a default
    // selection (DG-340 Phase 2 — FR1/AC1).
    //
    // DG-361 Phase 1 — FR2/AC2: default to `nen_so` (Nến số) when birthday
    // is checked and no prior selection exists; otherwise default to
    // `khong_nen`. The default lives in the local field only and is NOT
    // persisted until the user explicitly picks an option.
    final storedCandle = widget.item.attributes['candle_type']?.toString();
    if (storedCandle != null && storedCandle.isNotEmpty) {
      _candleType = storedCandle;
    } else if (_isBirthday) {
      _candleType = 'nen_so';
    } else {
      _candleType = 'khong_nen';
    }
    _notesFocus = FocusNode()..addListener(_onNotesFocusChange);
    _ageFocus = FocusNode()..addListener(_onAgeFocusChange);
    _priceFocus = FocusNode()..addListener(_onPriceFocusChange);
    _cashAmountFocus = FocusNode()..addListener(_onCashAmountFocusChange);
    _cashFeeFocus = FocusNode()..addListener(_onCashFeeFocusChange);
  }

  /// Assigned (COGS anchor) price for trưng bày markup — the existing
  /// `WorkItem.assignedPrice` if set, otherwise the product `basePrice`.
  double get _assignedPrice =>
      widget.item.assignedPrice ?? _findProduct()?.basePrice ?? 0;

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
    if (_priceFocus.hasFocus) return;
    if (_findProduct().isTrungBay) {
      _commitMarkupPrice();
    } else {
      final price = double.tryParse(_priceCtrl.text.trim());
      if (price != null) _editItem(unitPrice: price);
    }
  }

  /// Parses the thousands-input "Giá bán" field, enforces the floor warning,
  /// and clamps the selling price to the assigned price on save (FR2/AC1).
  /// A `unitPrice < assignedPrice` row is never persisted.
  void _commitMarkupPrice() {
    final text = _priceCtrl.text.trim();
    final thousands = int.tryParse(text);
    if (thousands == null) {
      setState(() => _floorWarning = null);
      return;
    }
    final selling = thousands.toDouble() * 1000;
    final assigned = _assignedPrice;
    final clamped = selling < assigned ? assigned : selling;
    setState(() {
      _floorWarning = selling < assigned ? OrdersLabels.markupFloorWarning : null;
      // Reflect the clamped value back into the thousands-input field so the
      // displayed text matches what was persisted.
      _priceCtrl.text = (clamped / 1000).toInt().toString();
    });
    _editItem(unitPrice: clamped);
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

  /// Persist the selected candle type into `attributes['candle_type']`
  /// (DG-340 Phase 2 — FR2). Preserves all other attributes by merging into
  /// the current item attributes. A "Không nến" selection (or birthday
  /// unchecked) removes the key entirely so AC7 (absent = no candle) holds.
  void _saveCandleType(String? value) {
    final next = Map<String, dynamic>.from(widget.item.attributes);
    if (_isBirthday && value != null && value != 'khong_nen') {
      next['candle_type'] = value;
    } else {
      next.remove('candle_type');
    }
    _editItem(attributes: next);
  }

  Future<void> _editItem({
    String? notes,
    double? unitPrice,
    double? assignedPrice,
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
            assignedPrice: assignedPrice,
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

  /// Opens `ProductPickerPage` (single-select, active products only) and
  /// applies the chosen product's `productId`/`productName` to the current
  /// work item (DG-414 Phase 4.3 / FR6). All other item fields (quantity,
  /// notes, attributes, blanks, price) are preserved — only `productId`
  /// and `productName` are sent in the PATCH (FR2/AC1/AC5).
  ///
  /// FR5 (DG-414 review UI-1): the swap button is gated by
  /// `_isSwapAllowed`, which is false for terminal statuses
  /// (delivered/cancelled) since the backend rejects those with 422.
  bool get _isSwapAllowed {
    final s = widget.item.status;
    return s != 'delivered' && s != 'cancelled';
  }

  Future<void> _changeProduct() async {
    final picked = <DraftOrderItem>[];
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductPickerPage(
          selectedItems: picked,
          onChanged: () {},
          singleSelect: true,
        ),
      ),
    );
    if (!mounted || picked.isEmpty) return;
    final draft = picked.first;
    try {
      await ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .edit(
            widget.item.id,
            productId: draft.product.productCode,
            productName: draft.product.name,
          );
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, normalizeApiError(e).message);
      }
    }
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
            child: const Text(SharedLabels.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              SharedLabels.remove,
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
          showTopSnackBar(context, '${SharedLabels.apiError}: $e');
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

  /// Renders the price chip [ChoiceChip] wrap for products with price chips,
  /// mirroring the create-flow `ExpandableItemCard` pattern (DG-342 Phase 2,
  /// FR3/AC2). Selecting a chip sets both the assigned (COGS anchor) price
  /// and the selling price to the chip price, clears any floor warning, and
  /// updates the price text field. For trung bay products the assigned
  /// price is also sent to the backend so `order_items.assigned_price` is
  /// persisted (FR4/AC8).
  List<Widget> _buildPriceChipSection(ThemeData theme, Product? product) {
    if (product == null || product.priceChips.isEmpty) return const [];
    final isTrungBay = product.isTrungBay;
    final selectedLabel =
        widget.item.attributes['price_chip_label']?.toString();
    return [
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: product.priceChips.map((chip) {
          final isSelected = selectedLabel == chip.label;
          final displayStock = chipDisplayStockQty(product, chip);
          final stockLabel = displayStock > 0 ? ' ($displayStock)' : '';
          return ChoiceChip(
            label: Text(
              '${chip.label} · ${formatVND(chip.price)}$stockLabel',
            ),
            selected: isSelected,
            onSelected: (nowSelected) {
              if (!nowSelected) return;
              final next = Map<String, dynamic>.from(widget.item.attributes);
              next['price_chip_label'] = chip.label;
              setState(() {
                _priceCtrl.text = isTrungBay
                    ? (chip.price / 1000).toInt().toString()
                    : chip.price.toInt().toString();
                // Selecting a chip resets the floor warning because the
                // selling price equals the assigned (COGS anchor) price.
                _floorWarning = null;
              });
              _editItem(
                unitPrice: chip.price,
                assignedPrice: isTrungBay ? chip.price : null,
                attributes: next,
              );
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 8),
    ];
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
                    message: OrdersLabels.giftToggleTooltip,
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
                              OrdersLabels.giftBadge,
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
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  tooltip: OrdersLabels.changeProduct,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  // FR5 (DG-414 review UI-1): the backend rejects product swaps on
                  // terminal items (delivered/cancelled) with 422. Disable the
                  // button in that case so the user does not hit a guaranteed
                  // failure path.
                  onPressed: _isSwapAllowed ? _changeProduct : null,
                ),
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
                  // Price chip ChoiceChip wrap — DG-342 Phase 2 (FR3/AC2).
                  // Mirrors the create-flow `ExpandableItemCard` pattern:
                  // selecting a chip sets both assignedPrice and unitPrice,
                  // clears the floor warning, and updates the price field.
                  ..._buildPriceChipSection(theme, product),
                  if (isTrungBay) ...[
                    // "Giá gốc" — non-editable assigned price (COGS anchor).
                    // DG-342 Phase 1 (edit order flow) — FR1/AC1.
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${OrdersLabels.giaGoc}: ${formatVND(_assignedPrice)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _priceCtrl,
                      focusNode: _priceFocus,
                      decoration: const InputDecoration(
                        labelText: OrdersLabels.giaBan,
                        helperText: OrdersLabels.markupThousandsHint,
                        border: OutlineInputBorder(),
                        suffixText: ',000đ',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    if (_floorWarning != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _floorWarning!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ] else
                    TextFormField(
                      controller: _priceCtrl,
                      focusNode: _priceFocus,
                      decoration: const InputDecoration(
                        labelText: OrdersLabels.itemPrice,
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
                      title: const Text(StockLabels.useInventory),
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
                      labelText: OrdersLabels.notes,
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
                      setState(() {
                        _isBirthday = newVal;
                        // DG-361 Phase 1 — FR2/AC2: when birthday is checked
                        // and the user has not yet picked a candle type
                        // (still the initial default), pre-select `nen_so`
                        // as the default. Not persisted until user interacts.
                        if (newVal &&
                            _candleType == 'khong_nen' &&
                            !widget.item.attributes
                                .containsKey('candle_type')) {
                          _candleType = 'nen_so';
                        }
                      });
                      _editItem(isBirthday: newVal);
                      // When birthday is unchecked, clear any stored
                      // candle_type so AC7 (absent = no candle) holds.
                      if (!newVal &&
                          widget.item.attributes
                              .containsKey('candle_type')) {
                        _saveCandleType(null);
                      }
                    },
                    title: const Text(OrdersLabels.isBirthday),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  if (_isBirthday) ...[
                    TextFormField(
                      controller: _ageCtrl,
                      focusNode: _ageFocus,
                      decoration: const InputDecoration(
                        labelText: OrdersLabels.birthdayAge,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    // Candle type radio group (DG-340 Phase 2 — FR1/AC1).
                    // Wired to item.attributes['candle_type'] via
                    // _saveCandleType (local-state + immediate-persist
                    // pattern, acceptable per CQ-3). Uses the shared
                    // CandleTypeRadioGroup widget (CQ-1).
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Text(
                        OrdersLabels.candleTypeSectionLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                      ),
                    ),
                    CandleTypeRadioGroup(
                      groupValue: _candleType,
                      onChanged: (v) {
                        setState(() => _candleType = v);
                        _saveCandleType(v);
                      },
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
                      title: const Text(OrdersLabels.rutTien),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    if (_rutTien) ...[
                      Row(
                        children: [
                          const Text('${OrdersLabels.soTienRut}: '),
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
                          const Text('${OrdersLabels.phiRutTien}: '),
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
