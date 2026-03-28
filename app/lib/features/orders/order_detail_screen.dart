import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/api/api_client.dart';
import '../../data/api/receipt_service.dart';
import '../../data/models/order.dart';
import '../../data/models/order_photo.dart';
import '../../data/models/payment_transaction.dart';
import '../../data/models/work_item.dart';
import '../../providers/order_providers.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/order_photo_section.dart';

const _statusColors = {
  'new': Colors.blue,
  'confirmed': Colors.orange,
  'in_progress': Colors.purple,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'completed': Colors.grey,
  'cancelled': Colors.red,
};

const _workItemStatusColors = {
  'pending': Colors.grey,
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'cancelled': Colors.red,
};

const _orderStatusRank = {
  'new': 0,
  'confirmed': 1,
  'in_progress': 2,
  'ready': 3,
  'delivered': 4,
  'completed': 5,
  'cancelled': 5,
};

const _workItemStatusRank = {
  'pending': 0,
  'working': 1,
  'ready': 2,
  'delivered': 3,
  'cancelled': 4,
};

bool _isBackward(String current, String target, Map<String, int> ranks) =>
    (ranks[target] ?? 0) < (ranks[current] ?? 0);

/// Shows a reason dialog for a status transition.
/// Returns the trimmed reason string, or null if cancelled.
Future<String?> _showReasonDialog(
  BuildContext context,
  String targetStatus,
) async {
  final ctrl = TextEditingController();
  final isCancel = targetStatus == 'cancelled';
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
                      backgroundColor: Theme.of(ctx).colorScheme.error,
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

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderRef});

  final String orderRef;

  void _showReceiptTypeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                VN.selectReceiptType,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text(VN.printOrderSummary),
              onTap: () {
                Navigator.pop(ctx);
                context.push(
                  '/orders/$orderRef/receipt?type=${ReceiptType.order.value}',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt),
              title: const Text(VN.printWorkTicket),
              onTap: () {
                Navigator.pop(ctx);
                context.push(
                  '/orders/$orderRef/receipt?type=${ReceiptType.workTicket.value}',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text(VN.printCustomerReceipt),
              onTap: () {
                Navigator.pop(ctx);
                context.push(
                  '/orders/$orderRef/receipt?type=${ReceiptType.customer.value}',
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderRef));

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.orderDetail),
        actions: [
          orderAsync.whenOrNull(
                data: (order) => IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: VN.editOrder,
                  onPressed: () async {
                    await context.push('/orders/$orderRef/edit');
                    ref.read(orderDetailProvider(orderRef).notifier).refresh();
                  },
                ),
              ) ??
              const SizedBox.shrink(),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: VN.printReceipt,
            onPressed: () => _showReceiptTypeSelector(context),
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(orderDetailProvider(orderRef).notifier).refresh(),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (order) => _OrderDetailBody(order: order),
      ),
    );
  }
}

class _OrderDetailBody extends ConsumerStatefulWidget {
  const _OrderDetailBody({required this.order});

  final Order order;

  @override
  ConsumerState<_OrderDetailBody> createState() => _OrderDetailBodyState();
}

class _OrderDetailBodyState extends ConsumerState<_OrderDetailBody> {
  bool _transitioning = false;
  bool _syncing = false;

  Order get order => widget.order;

  String _formatDueDisplay(String? date, String? time) {
    if (date == null) return '—';
    try {
      final d = DateFormat('yyyy-MM-dd').parse(date);
      final dateStr = DateFormat('dd/MM/yyyy').format(d);
      return time != null ? '$dateStr $time' : dateStr;
    } catch (_) {
      return time != null ? '$date $time' : date;
    }
  }

  String _deliveryLabel(String type) {
    switch (type) {
      case 'pickup':
        return VN.pickup;
      case 'bus':
        return VN.deliveryBus;
      case 'door':
        return VN.deliveryDoor;
      default:
        return type;
    }
  }

  Future<void> _onTransition(String targetStatus) async {
    String reason = '';
    if (_isBackward(order.status, targetStatus, _orderStatusRank) ||
        targetStatus == 'cancelled') {
      final r = await _showReasonDialog(context, targetStatus);
      if (r == null || !mounted) return;
      reason = r;
    }
    setState(() => _transitioning = true);
    try {
      await ref
          .read(orderDetailProvider(order.orderRef).notifier)
          .transitionTo(targetStatus, reason: reason);
      if (mounted) {
        showTopSnackBar(context, VN.orderStatusUpdated);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
      return;
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
    // Auto-sync work item status for single-item orders
    final items =
        ref.read(orderWorkItemsProvider(order.orderRef)).value ?? [];
    if (items.length == 1 && !_syncing) {
      _syncing = true;
      try {
        const orderToWorkItem = {
          'new': 'pending',
          'confirmed': 'pending',
          'in_progress': 'working',
          'ready': 'ready',
          'delivered': 'delivered',
          'completed': 'delivered',
          'cancelled': 'cancelled',
        };
        final mappedStatus = orderToWorkItem[targetStatus];
        if (mappedStatus != null) {
          final item = items.first;
          if (mappedStatus != item.status) {
            final syncReason =
                (_isBackward(item.status, mappedStatus, _workItemStatusRank) ||
                        mappedStatus == 'cancelled')
                    ? 'Tự động đồng bộ theo trạng thái đơn hàng'
                    : '';
            await ref
                .read(orderWorkItemsProvider(order.orderRef).notifier)
                .transitionStatus(item.id, mappedStatus, reason: syncReason);
            if (mounted) {
              showTopSnackBar(context, VN.autoSyncWorkItemStatus);
            }
          }
        }
      } catch (_) {
        // Auto-sync failure is silent
      } finally {
        _syncing = false;
      }
    }
  }

  double _computePaid(List<PaymentTransaction> txns) {
    var paid = 0.0;
    for (final t in txns) {
      if (t.type == 'refund') {
        paid -= t.amount;
      } else {
        paid += t.amount;
      }
    }
    return paid;
  }

  Future<void> _openAddPaymentSheet(double remaining) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordPaymentSheet(
        orderRef: order.orderRef,
        remaining: remaining,
      ),
    );
  }

  Future<void> _openTransactionDetail(PaymentTransaction txn) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TransactionDetailSheet(
        txn: txn,
        onEdit: () => _openEditPaymentSheet(txn),
      ),
    );
  }

  Future<void> _openEditPaymentSheet(PaymentTransaction txn) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditPaymentSheet(
        orderRef: order.orderRef,
        txn: txn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;
    final forwardTransitions = validTransitions[order.status] ?? [];
    // Backward transitions: all statuses with lower rank than current
    final currentRank = _orderStatusRank[order.status] ?? 0;
    final backwardTransitions = _orderStatusRank.entries
        .where((e) => e.value < currentRank && e.key != order.status)
        .map((e) => e.key)
        .toList();
    final transitions = [...forwardTransitions, ...backwardTransitions];

    final txnsAsync =
        ref.watch(orderPaymentTransactionsProvider(order.orderRef));
    final txns = txnsAsync.value ?? [];
    final amountPaid =
        txnsAsync.hasValue ? _computePaid(txns) : order.amountPaid;
    final remaining = order.totalPrice - amountPaid;
    final paymentColor = amountPaid >= order.totalPrice
        ? Colors.green
        : amountPaid > 0
            ? Colors.orange
            : theme.colorScheme.error;
    final paymentLabel = amountPaid >= order.totalPrice
        ? VN.paid
        : amountPaid > 0
            ? VN.partialPaid
            : VN.unpaid;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ── Status banner ─────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
              const SizedBox(width: 10),
              Text(
                statusLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                order.orderRef,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Order info ────────────────────────────────────────────────
        _SectionHeader(VN.customer),
        _InfoRow(
          icon: Icons.person_outline,
          label: VN.customerName,
          value: order.customerName,
        ),
        if (order.source.isNotEmpty)
          _InfoRow(
            icon: Icons.campaign_outlined,
            label: VN.orderSource,
            value: order.source,
          ),
        if (order.customerPhone.isNotEmpty)
          _InfoRow(
            icon: Icons.phone_outlined,
            label: VN.customerPhone,
            value: order.customerPhone,
          ),
        if (order.dueDate != null)
          _InfoRow(
            icon: Icons.schedule_outlined,
            label: VN.dueDate,
            value: _formatDueDisplay(order.dueDate, order.dueTime),
          ),
        _InfoRow(
          icon: Icons.local_shipping_outlined,
          label: VN.deliveryType,
          value: _deliveryLabel(order.deliveryType),
        ),
        if (order.deliveryAddress.isNotEmpty)
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: VN.deliveryAddress,
            value: order.deliveryAddress,
          ),
        if (order.notes.isNotEmpty)
          _InfoRow(
            icon: Icons.notes_outlined,
            label: VN.notes,
            value: order.notes,
          ),
        if (order.createdBy.isNotEmpty)
          _InfoRow(
            icon: Icons.person_outline,
            label: 'Người tạo',
            value: order.createdBy,
          ),
        const SizedBox(height: 16),

        // ── Items ─────────────────────────────────────────────────────
        _SectionHeader(VN.products),
        ...order.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        '${item.quantity} × ${formatVND(item.unitPrice)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatVND(item.quantity * item.unitPrice),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              VN.total,
              style: theme.textTheme.titleSmall,
            ),
            Text(
              formatVND(order.totalPrice),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Work items ────────────────────────────────────────────────
        _WorkItemSection(orderRef: order.orderRef, order: order),
        const SizedBox(height: 16),

        // ── Payment ───────────────────────────────────────────────────
        _SectionHeader(VN.payment),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: paymentColor.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: paymentColor.withAlpha(80)),
          ),
          child: Column(
            children: [
              _PaymentRow(
                label: VN.total,
                value: formatVND(order.totalPrice),
                valueStyle: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              _PaymentRow(
                label: VN.amountPaidLabel,
                value: formatVND(amountPaid),
                valueStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: amountPaid > 0 ? Colors.green : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _PaymentRow(
                label: VN.remainingLabel,
                value: formatVND(remaining),
                valueStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: remaining > 0 ? paymentColor : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: paymentColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    paymentLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: paymentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Add payment button ────────────────────────────────────────
        OutlinedButton.icon(
          onPressed: () => _openAddPaymentSheet(remaining),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(VN.addPayment),
        ),
        const SizedBox(height: 16),

        // ── Payment history ───────────────────────────────────────────
        _SectionHeader(VN.paymentHistory),
        if (txns.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              VN.noPaymentHistory,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          ...txns.map(
            (t) => _TransactionTile(
              txn: t,
              onTap: () => _openTransactionDetail(t),
            ),
          ),

        // ── Photos (all photos aggregated: order-level + per-item) ─────
        const SizedBox(height: 16),
        OrderPhotoSection(
          orderRef: order.orderRef,
          baseUrl: ref.watch(apiBaseUrlProvider),
        ),

        // ── Status actions ────────────────────────────────────────────
        if (transitions.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(VN.actions),
          if (_transitioning)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: transitions.map((t) {
                final isCancel = t == 'cancelled';
                final isBackwardBtn = backwardTransitions.contains(t);
                final isCompletedBlocked =
                    t == 'completed' && remaining > 0;
                if (isCancel) {
                  return OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                    onPressed: () => _onTransition(t),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(statusActionLabel(t)),
                  );
                }
                if (isBackwardBtn) {
                  return OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      side: BorderSide(color: Colors.orange.shade300),
                    ),
                    onPressed: () => _onTransition(t),
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text(statusActionLabel(t)),
                  );
                }
                return FilledButton.icon(
                  onPressed: isCompletedBlocked
                      ? () {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Chưa thanh toán đủ — còn thiếu ${formatVND(remaining)}',
                                ),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.only(
                                  bottom: 16, left: 16, right: 16,
                                ),
                              ),
                            );
                        }
                      : () => _onTransition(t),
                  style: isCompletedBlocked
                      ? FilledButton.styleFrom(
                          backgroundColor: theme.disabledColor,
                        )
                      : null,
                  icon: Icon(_transitionIcon(t), size: 18),
                  label: Text(statusActionLabel(t)),
                );
              }).toList(),
            ),
        ],
      ],
    );
  }

  IconData _transitionIcon(String targetStatus) {
    switch (targetStatus) {
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'in_progress':
        return Icons.bakery_dining_outlined;
      case 'ready':
        return Icons.done_all_outlined;
      case 'delivered':
        return Icons.local_shipping_outlined;
      case 'completed':
        return Icons.verified_outlined;
      default:
        return Icons.arrow_forward;
    }
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payment row ───────────────────────────────────────────────────────────────

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: valueStyle ?? theme.textTheme.bodySmall),
      ],
    );
  }
}

// ── Transaction tile ──────────────────────────────────────────────────────────

Color _txnColor(String type) {
  switch (type) {
    case 'deposit':
      return Colors.blue;
    case 'payment':
      return Colors.green;
    case 'full_payment':
      return Colors.teal;
    case 'refund':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.txn, this.onTap});

  final PaymentTransaction txn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _txnColor(txn.type);
    final typeLabel = txnTypeLabel(txn.type);
    final methodLabel = paymentMethodLabel(txn.method);

    String dateStr = '';
    if (txn.createdAt != null) {
      try {
        final dt = DateTime.parse(txn.createdAt!);
        dateStr = DateFormat('dd/MM HH:mm').format(dt);
      } catch (_) {
        dateStr = txn.createdAt!;
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(100)),
            ),
            child: Text(
              typeLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(methodLabel, style: theme.textTheme.bodySmall),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            txn.type == 'refund'
                ? '-${formatVND(txn.amount)}'
                : formatVND(txn.amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: txn.type == 'refund' ? Colors.orange : Colors.green,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ── Record payment bottom sheet ───────────────────────────────────────────────

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({required this.orderRef, required this.remaining});

  final String orderRef;
  final double remaining;

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  String _type = 'deposit';
  String _method = 'cash';
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  void _onTypeSelected(String type) {
    setState(() => _type = type);
    if (type == 'full_payment' && widget.remaining > 0) {
      // Display the amount in thousands (user types 200 → means 200,000)
      _amountCtrl.text = (widget.remaining / 1000).round().toString();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Multiply by 1000: staff types 200 → actual amount 200,000
    final amount = double.parse(_amountCtrl.text.trim()) * 1000;
    setState(() => _submitting = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .record(
            amount: amount,
            type: _type,
            method: _method,
            notes: _notesCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, VN.paymentRecorded);
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

    const types = [
      ('deposit', VN.txnTypeDeposit),
      ('payment', VN.txnTypePayment),
      ('full_payment', VN.txnTypeFullPayment),
      ('refund', VN.txnTypeRefund),
    ];
    const methods = [
      ('cash', VN.methodCash),
      ('transfer', VN.methodTransfer),
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(VN.addPayment, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(VN.txnType, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.$2),
                      selected: _type == t.$1,
                      onSelected: (_) => _onTypeSelected(t.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(VN.paymentMethod, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: methods
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m.$2),
                      selected: _method == m.$1,
                      onSelected: (_) => setState(() => _method = m.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: VN.paymentAmountLabel,
                border: OutlineInputBorder(),
                suffixText: ',000đ',
                helperText: 'Nhập nghìn đồng (VD: 200 = 200.000đ)',
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return VN.fieldRequired;
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return VN.invalidPrice;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: VN.paymentNotes,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(VN.addPayment),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Transaction detail sheet ──────────────────────────────────────────────────

class _TransactionDetailSheet extends StatelessWidget {
  const _TransactionDetailSheet({required this.txn, required this.onEdit});

  final PaymentTransaction txn;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _txnColor(txn.type);
    final typeLabel = txnTypeLabel(txn.type);
    final methodLabel = paymentMethodLabel(txn.method);

    String dateStr = '';
    if (txn.createdAt != null) {
      try {
        final dt = DateTime.parse(txn.createdAt!);
        dateStr = DateFormat('dd/MM/yyyy HH:mm').format(dt);
      } catch (_) {
        dateStr = txn.createdAt!;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withAlpha(100)),
                ),
                child: Text(
                  typeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                txn.type == 'refund'
                    ? '-${formatVND(txn.amount)}'
                    : formatVND(txn.amount),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: txn.type == 'refund' ? Colors.orange : Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DetailRow(label: VN.paymentMethod, value: methodLabel),
          if (dateStr.isNotEmpty)
            _DetailRow(label: VN.txnType, value: dateStr),
          if (txn.notes.isNotEmpty)
            _DetailRow(label: VN.txnNoteLabel, value: txn.notes),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onEdit();
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text(VN.editPayment),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// ── Edit payment bottom sheet ─────────────────────────────────────────────────

class _EditPaymentSheet extends ConsumerStatefulWidget {
  const _EditPaymentSheet({required this.orderRef, required this.txn});

  final String orderRef;
  final PaymentTransaction txn;

  @override
  ConsumerState<_EditPaymentSheet> createState() => _EditPaymentSheetState();
}

class _EditPaymentSheetState extends ConsumerState<_EditPaymentSheet> {
  late String _type;
  late String _method;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _type = widget.txn.type;
    _method = widget.txn.method;
    // Convert back from actual amount to thousands for display
    _amountCtrl = TextEditingController(
      text: (widget.txn.amount / 1000).round().toString(),
    );
    _notesCtrl = TextEditingController(text: widget.txn.notes);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountCtrl.text.trim()) * 1000;
    setState(() => _submitting = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .edit(
            widget.txn.id,
            amount: amount,
            type: _type,
            method: _method,
            notes: _notesCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, VN.paymentUpdated);
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

    const types = [
      ('deposit', VN.txnTypeDeposit),
      ('payment', VN.txnTypePayment),
      ('full_payment', VN.txnTypeFullPayment),
      ('refund', VN.txnTypeRefund),
    ];
    const methods = [
      ('cash', VN.methodCash),
      ('transfer', VN.methodTransfer),
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(VN.editPayment, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(VN.txnType, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.$2),
                      selected: _type == t.$1,
                      onSelected: (_) => setState(() => _type = t.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(VN.paymentMethod, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: methods
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m.$2),
                      selected: _method == m.$1,
                      onSelected: (_) => setState(() => _method = m.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: VN.paymentAmountLabel,
                border: OutlineInputBorder(),
                suffixText: ',000đ',
                helperText: 'Nhập nghìn đồng (VD: 200 = 200.000đ)',
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return VN.fieldRequired;
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return VN.invalidPrice;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: VN.paymentNotes,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(VN.editPayment),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Work item section ─────────────────────────────────────────────────────────

class _WorkItemSection extends ConsumerStatefulWidget {
  const _WorkItemSection({required this.orderRef, required this.order});

  final String orderRef;
  final Order order;

  @override
  ConsumerState<_WorkItemSection> createState() => _WorkItemSectionState();
}

class _WorkItemSectionState extends ConsumerState<_WorkItemSection> {
  bool _expanded = true;
  bool _transitioning = false;
  bool _syncing = false;

  String? _deriveOrderStatus(List<WorkItem> items) {
    if (items.isEmpty) return null;
    // Exclude cancelled items from min calculation
    final active = items.where((i) => i.status != 'cancelled').toList();
    if (active.isEmpty) return 'cancelled';
    // Find minimum rank work item status
    final minRank = active
        .map((i) => _workItemStatusRank[i.status] ?? 0)
        .reduce((a, b) => a < b ? a : b);
    // Map back to order status via the minimum work item status
    const workItemToOrder = {
      'pending': 'new',
      'working': 'in_progress',
      'ready': 'ready',
      'delivered': 'delivered',
    };
    final minWiStatus = active.firstWhere(
      (i) => (_workItemStatusRank[i.status] ?? 0) == minRank,
    ).status;
    return workItemToOrder[minWiStatus];
  }

  Future<void> _applyAutoUpdateOrderStatus(
    String suggestedStatus,
    List<WorkItem> items,
  ) async {
    final currentStatus =
        ref.read(orderDetailProvider(widget.orderRef)).value?.status ??
            widget.order.status;
    if (currentStatus == suggestedStatus) return;

    final statusLabel = statusMap[suggestedStatus] ?? suggestedStatus;
    final isMultiCake = items.length > 1;

    if (isMultiCake) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(VN.autoUpdateOrderTitle),
          content: Text(
            'Tất cả ${items.length} sản phẩm đã đạt ngưỡng.\n'
            'Cập nhật đơn hàng sang "$statusLabel"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(VN.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(VN.confirmStatusChange),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      final syncReason =
          (_isBackward(currentStatus, suggestedStatus, _orderStatusRank) ||
                  suggestedStatus == 'cancelled')
              ? 'Tự động cập nhật theo trạng thái sản phẩm'
              : '';
      await ref
          .read(orderDetailProvider(widget.orderRef).notifier)
          .transitionTo(
            suggestedStatus,
            reason: syncReason,
          );
      if (mounted) {
        showTopSnackBar(context, VN.orderStatusUpdated);
      }
    } catch (_) {
      // Auto-derive failure is silent — order may not be in a valid state
    }
  }

  Future<void> _onTransitionWorkItem(WorkItem item, String targetStatus) async {
    if (_transitioning) return;
    String reason = '';
    if (_isBackward(item.status, targetStatus, _workItemStatusRank)) {
      final r = await _showReasonDialog(context, targetStatus);
      if (r == null || !mounted) return;
      reason = r;
    }

    setState(() => _transitioning = true);
    try {
      await ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .transitionStatus(item.id, targetStatus, reason: reason);
      if (mounted) {
        showTopSnackBar(context, VN.workItemStatusChanged);
      }
      final items =
          ref.read(orderWorkItemsProvider(widget.orderRef)).value ?? [];
      if (items.length == 1 && !_syncing) {
        // Single-item order: direct bidirectional sync
        _syncing = true;
        try {
          const workItemToOrder = {
            'pending': 'new',
            'working': 'in_progress',
            'ready': 'ready',
            'delivered': 'delivered',
            'cancelled': 'cancelled',
          };
          final mappedStatus = workItemToOrder[targetStatus];
          if (mappedStatus != null) {
            final currentOrderStatus =
                ref.read(orderDetailProvider(widget.orderRef)).value?.status ??
                    widget.order.status;
            if (mappedStatus != currentOrderStatus) {
              final syncReason =
                  (_isBackward(currentOrderStatus, mappedStatus,
                              _orderStatusRank) ||
                          mappedStatus == 'cancelled')
                      ? 'Tự động đồng bộ theo trạng thái sản phẩm'
                      : '';
              await ref
                  .read(orderDetailProvider(widget.orderRef).notifier)
                  .transitionTo(mappedStatus, reason: syncReason);
              if (mounted) {
                showTopSnackBar(context, VN.autoSyncOrderStatus);
              }
            }
          }
        } catch (_) {
          // Auto-sync failure is silent
        } finally {
          _syncing = false;
        }
      } else if (items.length > 1) {
        // Multi-item order: heuristic derive
        final suggestedStatus = _deriveOrderStatus(items);
        if (suggestedStatus != null && mounted) {
          await _applyAutoUpdateOrderStatus(suggestedStatus, items);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    VN.workItemsSection,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          itemsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                VN.apiError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    VN.noWorkItems,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                );
              }
              final allPhotos = ref.watch(orderPhotosProvider(widget.orderRef)).value ?? [];
              final baseUrl = ref.watch(apiBaseUrlProvider);
              return Column(
                children: [
                  const SizedBox(height: 4),
                  ...items.map(
                    (item) => _WorkItemCard(
                      item: item,
                      photos: allPhotos.where((p) {
                        final wId = p.workItemId;
                        return wId != null && wId == int.tryParse(item.id);
                      }).toList(),
                      baseUrl: baseUrl,
                      onTransition: _transitioning
                          ? null
                          : (t) => _onTransitionWorkItem(item, t),
                      onTap: () => context.push(
                        '/orders/${widget.orderRef}/items/${item.id}',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _WorkItemCard extends StatelessWidget {
  const _WorkItemCard({
    required this.item,
    required this.onTransition,
    required this.photos,
    required this.baseUrl,
    required this.onTap,
  });

  final WorkItem item;
  final ValueChanged<String>? onTransition;
  final List<OrderPhoto> photos;
  final String baseUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _workItemStatusColors[item.status] ?? Colors.grey;
    final statusLabel = workItemStatusLabel(item.status);
    const allStatuses = ['pending', 'working', 'ready', 'delivered'];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status badge + product name + chevron
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withAlpha(100)),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.productName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
              // Qty × price
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${item.quantity} × ${formatVND(item.unitPrice)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              // Birthday badge + age
              if (item.isBirthday)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Text('🎂', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(
                        item.age != null
                            ? '${VN.birthdayWithAge} ${item.age} tuổi'
                            : VN.birthdayWithAge,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.pink.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              // Notes
              if (item.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.notes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              // Per-item photos
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                _WorkItemPhotoStrip(photos: photos, baseUrl: baseUrl),
              ],
              // Status transition chips
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: allStatuses.map((s) {
                  final isCurrent = s == item.status;
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
                      fontSize: 12,
                    ),
                    onSelected: isCurrent || onTransition == null
                        ? null
                        : (_) => onTransition!(s),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Per-item photo strip (read-only thumbnails in work item card) ─────────────

class _WorkItemPhotoStrip extends StatelessWidget {
  const _WorkItemPhotoStrip({required this.photos, required this.baseUrl});

  final List<OrderPhoto> photos;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, index) {
          final photo = photos[index];
          final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
          return GestureDetector(
            onTap: () => Navigator.of(ctx).push(
              MaterialPageRoute<void>(
                builder: (_) => OrderPhotoViewer(
                  photos: photos,
                  initialIndex: index,
                  baseUrl: baseUrl,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                url,
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.broken_image, size: 24),
                ),
              ),
            ),
          );
        },
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
