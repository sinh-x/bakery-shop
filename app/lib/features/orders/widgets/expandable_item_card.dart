// EXEMPT: 200-line threshold exceeded because DG-150 blocker: safe extraction of shell/collapsed/expanded sections risks cross-field validation regressions in active order draft wiring. Reviewed 2026-05-29.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../providers/order_providers.dart';
import '../utils/trung_bay_inventory_extensions.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'rut_tien_editor.dart';

class ExpandableItemCard extends StatefulWidget {
  const ExpandableItemCard({
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
  State<ExpandableItemCard> createState() => _ExpandableItemCardState();
}

class _ExpandableItemCardState extends State<ExpandableItemCard> {
  bool _expanded = true;
  bool _isBirthday = false;
  bool _isTrungBayMarkup = false;
  String? _floorWarning;
  late TextEditingController _notesCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _priceCtrl;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _isBirthday = widget.item.isBirthday;
    // AC1/AC7: default candle type to "Không nến" when none is set so the
    // radio group renders a default selection once is_birthday is checked.
    // FR6 (auto-check is_birthday for new cake items) is intentionally NOT
    // applied here: re-checking on every card build would override restored
    // drafts where the user explicitly unchecked birthday, violating the
    // Phase 2 guardrail ("Do NOT change existing birthday checkbox behavior")
    // and AC6. FR6 belongs at the item-creation boundary
    // (`product_picker_page._createDraftItem`), which is outside the three
    // files in scope for this phase.
    widget.item.candleType ??= 'khong_nen';
    _isTrungBayMarkup = widget.item.product.isTrungBay;
    _notesCtrl = TextEditingController(text: widget.item.notes);
    _ageCtrl = TextEditingController(text: widget.item.age);
    _priceCtrl = TextEditingController(
      text: _isTrungBayMarkup
          ? (widget.item.unitPrice / 1000).toInt().toString()
          : widget.item.unitPrice.toInt().toString(),
    );
    // Seed the assigned price (COGS anchor) for trưng bày products if it was
    // not already set by the picker. Defaults to the product base price.
    // See DG-296 Phase 4.
    if (_isTrungBayMarkup && widget.item.assignedPrice == null) {
      widget.item.assignedPrice = widget.item.product.basePrice;
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _ageCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickItemPhotos() async {
    final item = widget.item;
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    for (final f in files) {
      item.pendingPhotos.add(f);
    }
    if (mounted) {
      setState(() {});
      widget.onStateChanged();
    }
  }

  void _updateManualPrice(String text) {
    if (_isTrungBayMarkup) {
      // Trưng bày markup flow (DG-296 Phase 4): the price field is in thousands
      // of đồng (same style as the POS chip picker). Selling price may be set
      // upward from the assigned price; below-floor values are clamped.
      final thousands = int.tryParse(text.trim());
      if (thousands == null) {
        setState(() => _floorWarning = null);
        return;
      }
      final selling = thousands.toDouble() * 1000;
      final assigned = widget.item.assignedPrice ?? widget.item.product.basePrice;
      // FR3/AC3 price floor enforcement (DG-296 review-remediation): clamp the
      // selling price to the assigned price (COGS anchor) when staff entered a
      // lower value, instead of only warning. This prevents the wizard Stage 1
      // editor from producing a unitPrice < assignedPrice row that would then
      // be written back to the POS cart and submitted to the backend.
      final clamped = selling < assigned ? assigned : selling;
      widget.item.customUnitPrice = clamped;
      setState(() {
        _floorWarning = selling < assigned ? VN.markupFloorWarning : null;
      });
    } else {
      widget.item.customUnitPrice =
          double.tryParse(text.trim()) ?? widget.item.product.basePrice;
    }

    setState(() {});
    widget.onStateChanged();
  }

  bool get _isTrungBay => widget.item.product.isTrungBay;

  bool get _useInventory => widget.item.attributes.useInventory;

  String get _stockInlineText {
    final selectedChipId = widget.item.priceChipId;
    if (selectedChipId == null) return widget.item.product.stockInlineText;
    final selectedChip = widget.item.product.priceChips
        .where((chip) => chip.id == selectedChipId)
        .firstOrNull;
    final chipQty = selectedChip?.stockQty;
    if (chipQty == null) return VN.stockUnknown;
    return '${VN.stockRemaining}: $chipQty';
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
                  if (widget.item.product.priceChips.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: widget.item.product.priceChips.map((chip) {
                        final isSelected =
                            widget.item.attributes['price_chip_label'] ==
                                chip.label;
                        final stockLabel = chip.stockQty != null
                            ? ' (${chip.stockQty})'
                            : '';
                        return ChoiceChip(
                          label: Text(
                            '${chip.label} · ${formatVND(chip.price)}$stockLabel',
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _priceCtrl.text = _isTrungBayMarkup
                                  ? (chip.price / 1000).toInt().toString()
                                  : chip.price.toInt().toString();
                              widget.item.customUnitPrice = chip.price;
                              widget.item.priceChipId = chip.id;
                              widget.item.attributes['price_chip_label'] =
                                  chip.label;
                              // Selecting a chip resets the assigned (COGS
                              // anchor) and selling price to the chip price
                              // for trưng bày markup (DG-296 Phase 4).
                              if (_isTrungBayMarkup) {
                                widget.item.assignedPrice = chip.price;
                                _floorWarning = null;
                              }
                            });
                            widget.onStateChanged();
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Price
                  if (_isTrungBayMarkup) ...[
                    // "Giá gốc" — non-editable assigned price (COGS anchor).
                    // DG-296 Phase 4 (regular order flow).
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${VN.giaGoc}: ${formatVND(widget.item.assignedPrice ?? widget.item.product.basePrice)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _priceCtrl,
                      decoration: const InputDecoration(
                        labelText: VN.giaBan,
                        helperText: VN.markupThousandsHint,
                        border: OutlineInputBorder(),
                        suffixText: ',000đ',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: _updateManualPrice,
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
                  ] else
                    TextFormField(
                      controller: _priceCtrl,
                      decoration: const InputDecoration(
                        labelText: VN.itemPrice,
                        border: OutlineInputBorder(),
                        suffixText: 'đ',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: _updateManualPrice,
                    ),
                  const SizedBox(height: 8),
                  if (_isTrungBay) ...[
                    SwitchListTile.adaptive(
                      value: _useInventory,
                      onChanged: (value) {
                        // Lazy-save pattern: update local draft item state now,
                        // then persist later when parent save flow runs.
                        setState(() {
                          widget.item.attributes['useInventory'] = value
                              ? 'true'
                              : 'false';
                        });
                        widget.onStateChanged();
                      },
                      title: const Text(VN.useInventory),
                      subtitle: _useInventory ? Text(_stockInlineText) : null,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Enum attribute chip rows (DG-092 §8.4)
                  for (final ea in widget.item.product.enumAttributes)
                    if (ea.options.any((o) => o.active == 1)) ...[
                      Text(
                        ea.labelVi,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: ea.options.where((o) => o.active == 1).map((
                          opt,
                        ) {
                          final isSelected =
                              widget.item.attributes[ea.attributeType] ==
                              opt.valueVi;
                          return ChoiceChip(
                            label: Text(opt.valueVi),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  widget.item.attributes[ea.attributeType] =
                                      opt.valueVi;
                                });
                                widget.onStateChanged();
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
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
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onChanged: (v) => widget.item.age = v,
                    ),
                    const SizedBox(height: 8),
                    // Candle type radio group (DG-340 Phase 2 — FR1/AC1).
                    // Wired to DraftOrderItem.candleType (added in Phase 1).
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Text(
                        VN.candleTypeSectionLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ),
                    RadioGroup<String>(
                      groupValue: widget.item.candleType,
                      onChanged: (v) {
                        setState(() => widget.item.candleType = v);
                        widget.onStateChanged();
                      },
                      child: const Column(
                        children: [
                          RadioListTile<String>(
                            title: Text(VN.candleTypeNenSo),
                            value: 'nen_so',
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          RadioListTile<String>(
                            title: Text(VN.candleTypeNenXoan),
                            value: 'nen_xoan',
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          RadioListTile<String>(
                            title: Text(VN.candleTypeNenNho),
                            value: 'nen_nho',
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          RadioListTile<String>(
                            title: Text(VN.candleTypeKhongNen),
                            value: 'khong_nen',
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  RutTienEditor(
                    item: widget.item,
                    onStateChanged: widget.onStateChanged,
                  ),
                  // Per-item photo thumbnails
                  if (widget.item.pendingPhotos.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.item.pendingPhotos.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (ctx, idx) {
                          final xfile = widget.item.pendingPhotos[idx];
                          return Stack(
                            children: [
                              FutureBuilder<Uint8List>(
                                future: xfile.readAsBytes(),
                                builder: (ctx, snap) {
                                  if (!snap.hasData) {
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: const SizedBox(
                                        width: 70,
                                        height: 70,
                                      ),
                                    );
                                  }
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.memory(
                                      snap.data!,
                                      width: 70,
                                      height: 70,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                },
                              ),
                              Positioned(
                                top: 2,
                                left: 2,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    widget.item.pendingPhotos.removeAt(idx);
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
