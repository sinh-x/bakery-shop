// EXEMPT: 200-line threshold exceeded because DG-150 blocker: safe extraction of shell/collapsed/expanded sections risks cross-field validation regressions in active order draft wiring. Reviewed 2026-05-29.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../providers/order_providers.dart';
import '../utils/trung_bay_inventory_extensions.dart';
import 'package:bakery_app/shared/labels/orders.dart';
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
        widget.item.pendingPhotos.add(f);
      }
    });
    widget.onStateChanged();
  }

  void _updateManualPrice(String text) {
    final selectedLabel = widget.item.attributes['price_chip_label']
        ?.toString();
    widget.item.customUnitPrice =
        double.tryParse(text.trim()) ?? widget.item.product.basePrice;

    final manuallyClearPreset =
        selectedLabel != null &&
        !widget.item.product.priceChips.any(
          (chip) =>
              chip.label == selectedLabel &&
              chip.price == widget.item.customUnitPrice,
        );

    if (manuallyClearPreset) {
      widget.item.attributes.remove('price_chip_label');
      widget.item.priceChipId = null;
      if (mounted) {
        showTopSnackBar(context, 'Đã bỏ chọn mức giá nhanh khi chỉnh tay');
      }
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
                                chip.label &&
                            widget.item.customUnitPrice == chip.price;
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
                              _priceCtrl.text = chip.price.toInt().toString();
                              widget.item.customUnitPrice = chip.price;
                              widget.item.priceChipId = chip.id;
                              widget.item.attributes['price_chip_label'] =
                                  chip.label;
                            });
                            widget.onStateChanged();
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
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
