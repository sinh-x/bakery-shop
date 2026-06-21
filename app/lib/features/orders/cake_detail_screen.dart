// EXEMPT: 300-line threshold exceeded because DG-150 blocker: info/packing/attribute extraction here would require refactoring shared mutable detail-state paths beyond approved remediation scope. Reviewed 2026-05-29.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, debugPrintStack;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/receipt_service.dart';
import '../../data/models/work_item.dart';
import '../../data/services/printer_service.dart';
import '../../providers/events_provider.dart';
import '../../providers/order_providers.dart';
import '../../providers/paper_mode_provider.dart';
import '../../shared/utils/vnd_units.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/printer_picker_dialog.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'widgets/order_photo_section.dart';

const _workItemStatusColors = {
  'pending': Colors.grey,
  'confirmed': Colors.blue,
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'cancelled': Colors.red,
};

const _workItemStatusRank = {
  'pending': 0,
  'confirmed': 1,
  'working': 2,
  'ready': 3,
  'delivered': 4,
  'cancelled': 5,
};

bool _isBackwardItem(String current, String target) =>
    (_workItemStatusRank[target] ?? 0) < (_workItemStatusRank[current] ?? 0);

Future<String?> _showItemReasonDialog(
  BuildContext context,
  String targetStatus,
) async {
  final ctrl = TextEditingController();
  final isCancel = targetStatus == 'cancelled';
  final theme = Theme.of(context);
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isCancel ? VN.cancelOrderTitle : VN.statusReasonTitle),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: VN.statusReasonLabel,
              hintText: VN.statusReasonHint,
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            autofocus: true,
            onChanged: (_) => setS(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(VN.cancel),
            ),
            FilledButton(
              style: isCancel
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    )
                  : null,
              onPressed: ctrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(
                isCancel ? VN.confirmCancelAction : VN.confirmStatusChange,
              ),
            ),
          ],
        ),
      ),
    );
  } finally {
    ctrl.dispose();
  }
}

class CakeDetailScreen extends ConsumerStatefulWidget {
  const CakeDetailScreen({
    super.key,
    required this.orderRef,
    required this.workItemId,
  });

  final String orderRef;
  final String workItemId;

  @override
  ConsumerState<CakeDetailScreen> createState() => _CakeDetailScreenState();
}

class _CakeDetailScreenState extends ConsumerState<CakeDetailScreen> {
  bool _transitioning = false;
  bool _saving = false;

  Future<void> _onTransition(WorkItem item, String targetStatus) async {
    if (_transitioning) return;
    String reason = '';
    if (_isBackwardItem(item.status, targetStatus) ||
        targetStatus == 'cancelled') {
      final r = await _showItemReasonDialog(context, targetStatus);
      if (r == null || !mounted) return;
      reason = r;
    }
    setState(() => _transitioning = true);
    try {
      await ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .transitionStatus(item.id, targetStatus, reason: reason);
      // Refresh order detail to pick up server-synced order status
      ref.read(orderDetailProvider(widget.orderRef).notifier).refresh();
      if (mounted) {
        showTopSnackBar(context, VN.workItemStatusChanged);
      }

      // Prompt to print internal receipt if confirming and not yet printed
      if (targetStatus == 'confirmed' && mounted) {
        final order = ref.read(orderDetailProvider(widget.orderRef)).value;
        if (order != null && order.workTicketPrintedAt == null) {
          await _showInternalPrintPrompt(int.tryParse(item.id));
        }
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _showInternalPrintPrompt(int? itemId) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _InternalPrintDialog(orderRef: widget.orderRef, itemId: itemId),
    );
  }

  Future<void> _onSave(
    WorkItem item, {
    required String notes,
    required bool isBirthday,
    int? age,
    required double unitPrice,
    Map<String, dynamic>? attributes,
  }) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .edit(
            item.id,
            notes: notes,
            isBirthday: isBirthday,
            age: age,
            unitPrice: unitPrice,
            attributes: attributes,
          );
      if (mounted) {
        showTopSnackBar(context, VN.orderEditSaved);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
        rethrow;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.cakeDetail),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: VN.viewOrder,
            onPressed: () => context.push('/orders/${widget.orderRef}'),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: VN.printReceipt,
            onPressed: () => context.push(
              '/orders/${widget.orderRef}/receipt?type=${ReceiptType.workTicket.value}&item_id=${widget.workItemId}',
            ),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref
                    .read(orderWorkItemsProvider(widget.orderRef).notifier)
                    .refresh(),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (items) {
          final item = items
              .where((i) => i.id == widget.workItemId)
              .firstOrNull;
          if (item == null) {
            return Center(
              child: Text(
                'Không tìm thấy sản phẩm',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }
          return _CakeDetailBody(
            item: item,
            orderRef: widget.orderRef,
            baseUrl: baseUrl,
            transitioning: _transitioning,
            saving: _saving,
            onTransition: (t) => _onTransition(item, t),
            onSave: (notes, isBirthday, age, unitPrice, {attributes}) =>
                _onSave(
                  item,
                  notes: notes,
                  isBirthday: isBirthday,
                  age: age,
                  unitPrice: unitPrice,
                  attributes: attributes,
                ),
          );
        },
      ),
    );
  }
}

class _CakeDetailBody extends ConsumerStatefulWidget {
  const _CakeDetailBody({
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
  ConsumerState<_CakeDetailBody> createState() => _CakeDetailBodyState();
}

class _CakeDetailBodyState extends ConsumerState<_CakeDetailBody> {
  bool _editing = false;
  late TextEditingController _notesCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _cashAmountCtrl;
  late TextEditingController _cashFeeCtrl;
  late bool _isBirthday;
  late bool _rutTien;

  static const int _defaultCashFee = 20000;
  static const int _cashFeeStep = 5000;
  static const int _cashAmountStep = 100000;
  static const int _minCashAmount = 100000;
  bool _editingCashAmount = false;

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
    Map<String, dynamic>? attributes;
    if (_rutTien) {
      attributes = {
        'rut_tien': 'true',
        'cash_amount': _cashAmountCtrl.text.trim(),
        'cash_fee': _cashFeeCtrl.text.trim().isNotEmpty
            ? _cashFeeCtrl.text.trim()
            : '$_defaultCashFee',
      };
    } else if (widget.item.attributes.containsKey('rut_tien')) {
      // F17: Toggle-off removes keys entirely
      attributes = {};
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
    final statusColor =
        _workItemStatusColors[widget.item.status] ?? Colors.grey;
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
              final color = _workItemStatusColors[s] ?? Colors.grey;
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

// ── Internal Receipt Print Dialog (work item confirm prompt) ────────────────

class _InternalPrintDialog extends ConsumerStatefulWidget {
  const _InternalPrintDialog({required this.orderRef, this.itemId});

  final String orderRef;
  final int? itemId;

  @override
  ConsumerState<_InternalPrintDialog> createState() =>
      _InternalPrintDialogState();
}

class _InternalPrintDialogState extends ConsumerState<_InternalPrintDialog> {
  bool _printing = false;
  String _statusText = '';

  Future<void> _printInternal() async {
    setState(() {
      _printing = true;
      _statusText = VN.fetchingInternalReceipt;
    });

    try {
      if (kIsWeb) {
        final receiptService = ref.read(receiptServiceProvider);
        final printedBy = ref.read(loggedByProvider);
        await receiptService.printReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.workTicket,
          itemId: widget.itemId,
          printedBy: printedBy,
        );
        ref.read(orderDetailProvider(widget.orderRef).notifier).refresh();
        if (mounted) {
          showTopSnackBar(context, VN.internalReceiptPrinted);
          Navigator.pop(context);
        }
        return;
      }

      final printerService = ref.read(printerServiceProvider);
      await printerService.init();

      final receiptService = ref.read(receiptServiceProvider);
      final internalBytes = await receiptService.fetchReceipt(
        orderRef: widget.orderRef,
        type: ReceiptType.workTicket,
        itemId: widget.itemId,
      );

      setState(() => _statusText = VN.printingInternalReceipt);

      PrinterPickerResult result = PrinterPickerResult.cancelled;
      if (printerService.lastPrinterMac != null) {
        try {
          await printerService.connect(printerService.lastPrinterMac!);
          final paperMode = ref.read(paperModeProvider).asData?.value ?? 'label';
          final trailMm = ref.read(trailMmProvider).asData?.value ?? 20;
          await printerService.printImage(internalBytes,
              paperMode: paperMode, trailMm: trailMm);
          result = PrinterPickerResult.success;
        } catch (_) {
          // Fall through to picker
        }
      }

      if (result != PrinterPickerResult.success && mounted) {
        result = await showPrinterPickerDialog(
          context: context,
          imageBytes: internalBytes,
          printerService: printerService,
        );
      }

      if (result == PrinterPickerResult.success) {
        ref.read(orderDetailProvider(widget.orderRef).notifier).refresh();
        if (mounted) {
          showTopSnackBar(context, VN.internalReceiptPrinted);
          Navigator.pop(context);
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _printing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(VN.printChecklistTitle),
      content: _printing
          ? SizedBox(
              height: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _statusText,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : const Text(VN.printInternalPrompt),
      actions: [
        TextButton(
          onPressed: _printing ? null : () => Navigator.pop(context),
          child: const Text(VN.printSkip),
        ),
        if (!_printing)
          FilledButton(onPressed: _printInternal, child: const Text(VN.print)),
      ],
    );
  }
}
