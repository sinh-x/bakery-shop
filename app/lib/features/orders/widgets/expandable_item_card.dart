import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../providers/order_providers.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

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
