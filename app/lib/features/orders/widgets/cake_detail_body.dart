import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/enum_attribute.dart';
import '../../../data/models/work_item.dart';
import '../../../providers/order_providers.dart';
import '../../../providers/products_provider.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/utils/vnd_units.dart';
import '../../../shared/widgets/vietnamese_labels.dart';
import 'cake_detail_blank_section.dart';
import 'candle_type_radio_group.dart';
import 'enum_attribute_display.dart';
import 'order_photo_section.dart';

/// Status → color map for work item status chips (shared between the detail
/// body and the status transition chips).
const Map<String, Color> workItemStatusColors = {
  'pending': Colors.grey,
  'confirmed': Colors.blue,
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'cancelled': Colors.red,
};

/// Renders the scrollable body of the CakeDetailScreen (DG-294).
///
/// Extracted from `cake_detail_screen.dart` (NFR1) to keep the screen widget
/// under 500 lines. Owns the edit-mode form state (price/birthday/notes/cash
/// fields), renders the read-mode summary, the blank (phôi) section, the
/// per-item photos, and the status transition chips.
class CakeDetailBody extends ConsumerStatefulWidget {
  const CakeDetailBody({
    super.key,
    required this.item,
    required this.orderRef,
    required this.baseUrl,
    required this.transitioning,
    required this.saving,
    required this.onTransition,
    required this.onSave,
  });

  final WorkItem item;
  final String orderRef;
  final String baseUrl;
  final bool transitioning;
  final bool saving;
  final ValueChanged<String> onTransition;
  final Future<void> Function(
    String notes,
    bool isBirthday,
    int? age,
    double unitPrice, {
    Map<String, dynamic>? attributes,
  })
  onSave;

  @override
  ConsumerState<CakeDetailBody> createState() => _CakeDetailBodyState();
}

class _CakeDetailBodyState extends ConsumerState<CakeDetailBody> {
  bool _editing = false;
  late TextEditingController _notesCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _cashAmountCtrl;
  late TextEditingController _cashFeeCtrl;
  late bool _isBirthday;
  late bool _rutTien;
  String? _candleType;

  static const int _defaultCashFee = 20000;
  static const int _cashFeeStep = 5000;
  static const int _cashAmountStep = 100000;
  static const int _minCashAmount = 100000;
  bool _editingCashAmount = false;

  /// Resolve the enum attributes defined on the product matching the work
  /// item's `productId`. Mirrors `OrderDetailGeneralTab._enumAttributesFor`
  /// so the cake detail body shows the same enum lines (DG-362 Phase 3 /
  /// FR2 / AC2).
  List<EnumAttribute> _enumAttributesFor(
    String productId,
    WidgetRef ref,
  ) {
    if (productId.isEmpty) return const [];
    final products = ref.watch(productsProvider).asData?.value ?? const [];
    for (final p in products) {
      if (p.id.toString() == productId || p.productCode == productId) {
        return p.enumAttributes;
      }
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController();
    _ageCtrl = TextEditingController();
    _priceCtrl = TextEditingController();
    _cashAmountCtrl = TextEditingController();
    _cashFeeCtrl = TextEditingController();
    _isBirthday = false;
    _rutTien = false;
    _candleType = null;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _ageCtrl.dispose();
    _priceCtrl.dispose();
    _cashAmountCtrl.dispose();
    _cashFeeCtrl.dispose();
    super.dispose();
  }

  void _startEdit() {
    _notesCtrl.text = widget.item.notes;
    _ageCtrl.text = widget.item.age?.toString() ?? '';
    // ×1000 convention: store 150000, display 150
    _priceCtrl.text = widget.item.unitPrice > 0
        ? vndToThousands(widget.item.unitPrice).toStringAsFixed(0)
        : '';
    _isBirthday = widget.item.isBirthday;
    // F15: Initialize rut tien state from attributes['rut_tien'] directly
    final cashAmount = widget.item.attributes['cash_amount']?.toString() ?? '';
    final cashFee = widget.item.attributes['cash_fee']?.toString() ?? '';
    _cashAmountCtrl.text = cashAmount;
    _cashFeeCtrl.text = cashFee.isNotEmpty ? cashFee : '$_defaultCashFee';
    _rutTien = widget.item.attributes['rut_tien']?.toString() == 'true';
    final storedCandle = widget.item.attributes['candle_type']?.toString();
    // AC1/AC7: default selection is "Không nến" (no candle). A stored
    // candle_type takes precedence; absence falls back to the explicit
    // "khong_nen" radio value so the group renders a default selection.
    _candleType = storedCandle?.isNotEmpty == true ? storedCandle : 'khong_nen';
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    setState(() => _editing = false);
  }

  Future<void> _submit() async {
    final rawPrice = double.tryParse(_priceCtrl.text.trim());
    final unitPrice = rawPrice != null
        ? vndFromThousands(rawPrice)
        : widget.item.unitPrice;
    final age = _isBirthday ? int.tryParse(_ageCtrl.text.trim()) : null;
    final hasCandle =
        _isBirthday && _candleType != null && _candleType != 'khong_nen';
    // Determine whether candle_type changed relative to the stored value.
    final storedCandle = widget.item.attributes['candle_type']?.toString();
    final candleChanged = (hasCandle ? _candleType : null) != storedCandle;
    Map<String, dynamic>? attributes;
    if (_rutTien) {
      attributes = {
        'rut_tien': 'true',
        'cash_amount': _cashAmountCtrl.text.trim(),
        'cash_fee': _cashFeeCtrl.text.trim().isNotEmpty
            ? _cashFeeCtrl.text.trim()
            : '$_defaultCashFee',
      };
      if (hasCandle) {
        attributes['candle_type'] = _candleType;
      }
    } else if (widget.item.attributes.containsKey('rut_tien')) {
      // F17: Toggle-off removes cash keys entirely (existing behavior).
      attributes = {};
    } else if (candleChanged) {
      // No rut_tien change: only patch candle_type, preserving everything else.
      attributes = Map<String, dynamic>.from(widget.item.attributes);
      if (hasCandle) {
        attributes['candle_type'] = _candleType;
      } else {
        attributes.remove('candle_type');
      }
    }

    try {
      await widget.onSave(
        _notesCtrl.text.trim(),
        _isBirthday,
        age,
        unitPrice,
        attributes: attributes,
      );
      if (mounted) setState(() => _editing = false);
    } catch (error, stackTrace) {
      debugPrint('cake_detail: save failed for item ${widget.item.id}: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Error already shown by parent via snackbar; stay in edit mode
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = workItemStatusColors[widget.item.status] ?? Colors.grey;
    final statusLabel = workItemStatusLabel(widget.item.status);
    const allStatuses = [
      'pending',
      'confirmed',
      'working',
      'ready',
      'delivered',
      'cancelled',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // ── Status chip ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withAlpha(120)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Product name (always read-only) ───────────────────────────
        Text(
          widget.item.productName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),

        if (!_editing) ...[
          // ── Read mode: qty × price ────────────────────────────────
          Text(
            '${widget.item.quantity} × ${formatVND(widget.item.unitPrice)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),

          // ── Enum attribute lines (DG-362 Phase 3 / FR2 / AC2) ────
          ...buildEnumAttributeLines(
            context,
            widget.item.attributes,
            _enumAttributesFor(widget.item.productId, ref),
          ),

          // ── Birthday / age ────────────────────────────────────────
          if (widget.item.isBirthday) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('🎂', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  widget.item.age != null
                      ? '${VN.birthdayWithAge} ${widget.item.age} tuổi'
                      : VN.birthdayWithAge,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.pink.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          // ── Candle type (DG-340 Phase 3 — FR3/AC3) ────────────────
          if (widget.item.attributes['candle_type'] != null &&
              widget.item.attributes['candle_type'].toString().isNotEmpty &&
              widget.item.attributes['candle_type'].toString() != 'khong_nen') ...[
            const SizedBox(height: 6),
            Text(
              'Nến: ${VN.candleTypeLabel(widget.item.attributes['candle_type'].toString())}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.pink.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          // ── Cash info ──────────────────────────────────────────────
          if (widget.item.attributes['cash_amount'] != null &&
              widget.item.attributes['cash_amount'].toString().isNotEmpty &&
              widget.item.attributes['cash_amount'].toString() != '0') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('💵', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  '${VN.rutTien}: ${formatVND((int.tryParse(widget.item.attributes['cash_amount'].toString()) ?? 0).toDouble())}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (widget.item.attributes['cash_fee'] != null &&
                widget.item.attributes['cash_fee'].toString().isNotEmpty &&
                widget.item.attributes['cash_fee'].toString() != '0')
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: Text(
                  '${VN.phiRutTien}: ${formatVND((int.tryParse(widget.item.attributes['cash_fee'].toString()) ?? 0).toDouble())}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            // Rut tien transaction summary (F9)
            Builder(
              builder: (_) {
                final txnsAsync = ref.watch(
                  orderPaymentTransactionsProvider(widget.orderRef),
                );
                final txns = txnsAsync.value ?? [];
                final target =
                    int.tryParse(
                      widget.item.attributes['cash_amount'].toString(),
                    ) ??
                    0;
                final received = txns
                    .where((t) => t.type == 'tien_rut')
                    .fold<double>(0, (sum, t) => sum + t.amount);
                final isFullyReceived = received >= target;
                return Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: Text(
                    'Tiền rút đã nhận: ${formatVND(received)} / ${formatVND(target.toDouble())}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isFullyReceived
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ],

          // ── Notes ─────────────────────────────────────────────────
          if (widget.item.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _SectionLabel('Ghi chú'),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.item.notes, style: theme.textTheme.bodyMedium),
            ),
          ],

          // ── Edit button ───────────────────────────────────────────
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: widget.saving ? null : _startEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Chỉnh sửa'),
          ),
        ] else ...[
          // ── Edit mode ─────────────────────────────────────────────

          // Unit price field
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Đơn giá (×1.000đ)',
              hintText: 'VD: 150 → 150.000đ',
              border: OutlineInputBorder(),
              suffixText: '.000đ',
              isDense: true,
            ),
          ),

          // Birthday toggle
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _isBirthday,
                onChanged: (v) => setState(() {
                  _isBirthday = v ?? false;
                  if (!_isBirthday) _ageCtrl.clear();
                }),
              ),
              const Text(VN.isBirthday),
            ],
          ),

          // Age field (only when birthday)
          if (_isBirthday) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _ageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: VN.birthdayAge,
                hintText: 'VD: 7',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            // Candle type radio group (DG-340 Phase 2 — FR1/AC1).
            // Shown only when is_birthday is checked. Default selection is
            // "Không nến" (no candle); selecting a real type persists the
            // value under `attributes['candle_type']` (FR2/AC7).
            const SizedBox(height: 8),
            const _SectionLabel(VN.candleTypeSectionLabel),
            CandleTypeRadioGroup(
              groupValue: _candleType,
              onChanged: (v) => setState(() => _candleType = v),
            ),
          ],

          // Rut tien toggle
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _rutTien,
                onChanged: (v) => setState(() {
                  _rutTien = v ?? false;
                  if (!_rutTien) {
                    _cashAmountCtrl.clear();
                  }
                }),
              ),
              const Text(VN.rutTien),
            ],
          ),

          // Cash fields (only when rut tien is enabled)
          if (_rutTien) ...[
            const SizedBox(height: 8),
            // Cash amount stepper: [-] [amount] [+] with 100k step
            Row(
              children: [
                const Text('${VN.soTienRut}: '),
                IconButton.filled(
                  onPressed: () {
                    final current = int.tryParse(_cashAmountCtrl.text) ?? 0;
                    if (current > _minCashAmount) {
                      final next = current - _cashAmountStep;
                      final clamped = next < _minCashAmount
                          ? _minCashAmount
                          : next;
                      setState(() {
                        _cashAmountCtrl.text = '$clamped';
                        _editingCashAmount = false;
                      });
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
                    onTap: () => setState(() => _editingCashAmount = true),
                    child: _editingCashAmount
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: TextField(
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
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(9),
                              ],
                              onEditingComplete: () {
                                final val =
                                    int.tryParse(_cashAmountCtrl.text) ?? 0;
                                if (val < _minCashAmount && val != 0) {
                                  _cashAmountCtrl.text = '$_minCashAmount';
                                }
                                setState(() => _editingCashAmount = false);
                              },
                            ),
                          )
                        : Center(
                            child: Text(
                              _cashAmountCtrl.text.isEmpty ||
                                      _cashAmountCtrl.text == '0'
                                  ? '0đ'
                                  : formatVND(
                                      (int.tryParse(_cashAmountCtrl.text) ?? 0)
                                          .toDouble(),
                                    ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                  ),
                ),
                IconButton.filled(
                  onPressed: () {
                    final current = int.tryParse(_cashAmountCtrl.text) ?? 0;
                    final next = current + _cashAmountStep;
                    final clamped = next < _minCashAmount
                        ? _minCashAmount
                        : next;
                    setState(() {
                      _cashAmountCtrl.text = '$clamped';
                      _editingCashAmount = false;
                    });
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
                const Text('${VN.phiRutTien}: '),
                IconButton.filled(
                  onPressed: () {
                    final current = int.tryParse(_cashFeeCtrl.text) ?? 0;
                    if (current >= _cashFeeStep) {
                      setState(() {
                        _cashFeeCtrl.text = '${current - _cashFeeStep}';
                      });
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
                      (int.tryParse(_cashFeeCtrl.text) ?? _defaultCashFee)
                          .toDouble(),
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton.filled(
                  onPressed: () {
                    final current =
                        int.tryParse(_cashFeeCtrl.text) ?? _defaultCashFee;
                    setState(() {
                      _cashFeeCtrl.text = '${current + _cashFeeStep}';
                    });
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
          ],

          // Notes field
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: VN.notes,
              hintText: 'Ghi chú cho sản phẩm này...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          // Save / Cancel buttons
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: widget.saving ? null : _submit,
                  child: widget.saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(VN.save),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.saving ? null : _cancelEdit,
                  child: const Text(VN.cancel),
                ),
              ),
            ],
          ),
        ],

        // ── Blank (phôi bánh) assignments ───────────────────────────────
        const SizedBox(height: 16),
        CakeDetailBlankSection(
          orderRef: widget.orderRef,
          item: widget.item,
          editing: _editing,
          onAddBlank: ref
              .read(orderWorkItemsProvider(widget.orderRef).notifier)
              .addBlank,
          onUpdateBlank: ref
              .read(orderWorkItemsProvider(widget.orderRef).notifier)
              .updateBlank,
          onDeleteBlank: ref
              .read(orderWorkItemsProvider(widget.orderRef).notifier)
              .removeBlank,
        ),

        // ── Per-item photos ───────────────────────────────────────────
        const SizedBox(height: 16),
        OrderPhotoSection(
          orderRef: widget.orderRef,
          baseUrl: widget.baseUrl,
          workItemId: int.tryParse(widget.item.id),
        ),

        // ── Status transitions ────────────────────────────────────────
        const SizedBox(height: 16),
        const _SectionLabel('Chuyển trạng thái'),
        const SizedBox(height: 8),
        if (widget.transitioning)
          const Center(child: CircularProgressIndicator())
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allStatuses.map((s) {
              final isCurrent = s == widget.item.status;
              final color = workItemStatusColors[s] ?? Colors.grey;
              return FilterChip(
                label: Text(workItemStatusLabel(s)),
                selected: isCurrent,
                selectedColor: color.withAlpha(40),
                checkmarkColor: color,
                side: BorderSide(
                  color: isCurrent ? color : Colors.grey.shade300,
                ),
                labelStyle: TextStyle(
                  color: isCurrent ? color : null,
                  fontWeight: isCurrent ? FontWeight.bold : null,
                ),
                onSelected: isCurrent ? null : (_) => widget.onTransition(s),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}