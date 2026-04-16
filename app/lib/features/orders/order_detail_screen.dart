import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api/api_client.dart';
import '../../data/api/order_service.dart';
import '../../data/api/receipt_service.dart';
import '../../data/models/order.dart';
import '../../data/models/order_photo.dart';
import '../../data/models/payment_transaction.dart';
import '../../data/models/work_item.dart';
import '../../data/services/printer_service.dart';
import '../../providers/order_providers.dart';
import '../../shared/utils/phone_formatter.dart';
import '../../shared/widgets/printer_picker_dialog.dart';
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
  'confirmed': Colors.blue,
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
  'confirmed': 1,
  'working': 2,
  'ready': 3,
  'delivered': 4,
  'cancelled': 5,
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

  void _showReceiptTypeSelector(BuildContext context, WidgetRef ref) {
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
              leading: const Icon(Icons.receipt),
              title: const Text(VN.printWorkTicket),
              onTap: () {
                Navigator.pop(ctx);
                final allItems =
                    ref.read(orderWorkItemsProvider(orderRef)).value ?? [];
                final workItems = allItems.where((i) => !i.isExtra).toList();
                if (workItems.length == 1) {
                  context.push(
                    '/orders/$orderRef/receipt?type=${ReceiptType.workTicket.value}&item_id=${workItems.first.id}',
                  );
                } else if (workItems.isNotEmpty) {
                  _showItemPicker(context, workItems);
                }
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
            if (ref.read(orderDetailProvider(orderRef)).value?.deliveryType ==
                'bus')
              ListTile(
                leading: const Icon(Icons.local_shipping),
                title: const Text(VN.printBusLabel),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/orders/$orderRef/receipt?type=${ReceiptType.busLabel.value}',
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.store),
              title: const Text(VN.printShopReceipt),
              onTap: () {
                Navigator.pop(ctx);
                context.push(
                  '/orders/$orderRef/receipt?type=${ReceiptType.shop.value}',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delivery_dining),
              title: Text(VN.printDeliveryReceipt),
              onTap: () {
                Navigator.pop(ctx);
                context.push(
                  '/orders/$orderRef/receipt?type=${ReceiptType.delivery.value}',
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showItemPicker(BuildContext context, List<WorkItem> items) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chọn sản phẩm',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final item in items)
              ListTile(
                leading: const Icon(Icons.cake_outlined),
                title: Text(item.productName),
                subtitle: Text('SL: ${item.quantity}'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/orders/$orderRef/receipt?type=${ReceiptType.workTicket.value}&item_id=${item.id}',
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
            onPressed: () => _showReceiptTypeSelector(context, ref),
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
      // Refresh work items to pick up server-synced extras
      ref.read(orderWorkItemsProvider(order.orderRef).notifier).refresh();
      if (mounted) {
        showTopSnackBar(context, VN.orderStatusUpdated);
      }
      // Flow A: after new → confirmed transition, show print checklist dialog
      if (targetStatus == 'confirmed' && order.status == 'new') {
        await _showPrintChecklistDialog();
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _showPrintChecklistDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PrintChecklistDialog(orderRef: order.orderRef),
    );
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
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phone_outlined, size: 16,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: Text(
                    VN.customerPhone,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final digits =
                          order.customerPhone.replaceAll(RegExp(r'\D'), '');
                      launchUrl(Uri.parse('tel:$digits'));
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatPhone(order.customerPhone),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.phone, size: 16,
                            color: Theme.of(context).colorScheme.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
        ...order.items.where((item) => !item.isExtra).map(
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
                      // Cash info (F27)
                      if (item.attributes['cash_amount'] != null && item.attributes['cash_amount'].toString().isNotEmpty && item.attributes['cash_amount'].toString() != '0') ...[
                        const SizedBox(height: 2),
                        Text(
                          '${VN.rutTien}: ${formatVND((int.tryParse(item.attributes['cash_amount'].toString()) ?? 0).toDouble())}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (item.attributes['cash_fee'] != null && item.attributes['cash_fee'].toString().isNotEmpty && item.attributes['cash_fee'].toString() != '0')
                          Text(
                            '${VN.phiRutTien}: ${formatVND((int.tryParse(item.attributes['cash_fee'].toString()) ?? 0).toDouble())}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade700,
                            ),
                          ),
                      ],
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
        if (order.items.any((item) => item.isExtra)) ...[
          const SizedBox(height: 12),
          _SectionHeader(VN.extras),
          ...order.items.where((item) => item.isExtra).map(
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
                  if (item.isGift)
                    Text(
                      VN.giftBadge,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
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
        ],
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
        if (order.shippingFee > 0) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${VN.shippingFee}:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              Text(
                formatVND(order.shippingFee),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
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
              if (order.shippingFee > 0) ...[
                _PaymentRow(
                  label: VN.shippingFee,
                  value: formatVND(order.shippingFee),
                  valueStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 4),
              ],
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
      // Refresh order detail to pick up server-synced order status
      ref.read(orderDetailProvider(widget.orderRef).notifier).refresh();
      if (mounted) {
        showTopSnackBar(context, VN.workItemStatusChanged);
      }

      // Prompt to print internal receipt if confirming and not yet printed
      if (targetStatus == 'confirmed' &&
          widget.order.workTicketPrintedAt == null &&
          mounted) {
        await _showInternalPrintPrompt(int.tryParse(item.id));
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
      builder: (ctx) => _InternalPrintDialog(
        orderRef: widget.orderRef,
        itemId: itemId,
      ),
    );
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
              final regularItems = items.where((i) => !i.isExtra).toList();
              final extraItems = items.where((i) => i.isExtra).toList();
              final allPhotos = ref.watch(orderPhotosProvider(widget.orderRef)).value ?? [];
              final baseUrl = ref.watch(apiBaseUrlProvider);
              return Column(
                children: [
                  const SizedBox(height: 4),
                  ...regularItems.map(
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
                  if (extraItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        VN.extras,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: extraItems.map((item) {
                        final label = item.isGift
                            ? '${item.productName} (Tặng)'
                            : '${item.productName} (${formatVND(item.unitPrice)})';
                        return Chip(
                          avatar: Icon(
                            item.isGift ? Icons.card_giftcard : Icons.sell,
                            size: 14,
                            color: item.isGift ? Colors.green : theme.colorScheme.outline,
                          ),
                          label: Text(
                            item.quantity > 1 ? '$label ×${item.quantity}' : label,
                            style: theme.textTheme.bodySmall,
                          ),
                          backgroundColor: item.isGift
                              ? Colors.green.withValues(alpha: 0.1)
                              : theme.colorScheme.surfaceContainerHighest,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
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
    const allStatuses = ['pending', 'confirmed', 'working', 'ready', 'delivered', 'cancelled'];

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
                  if (item.isExtra) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.isGift
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.card_giftcard,
                            size: 10,
                            color: item.isGift ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            item.isGift ? VN.giftBadge : 'Trả phí',
                            style: TextStyle(
                              fontSize: 9,
                              color: item.isGift ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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

// ── Print Checklist Dialog (Flow A) ─────────────────────────────────────────

class _PrintChecklistDialog extends ConsumerStatefulWidget {
  const _PrintChecklistDialog({required this.orderRef});

  final String orderRef;

  @override
  ConsumerState<_PrintChecklistDialog> createState() =>
      _PrintChecklistDialogState();
}

class _PrintChecklistDialogState extends ConsumerState<_PrintChecklistDialog> {
  bool _printInternal = true;
  bool _printCustomer = true;
  bool _printing = false;
  String _statusText = '';

  Future<void> _printSelected() async {
    if (!_printInternal && !_printCustomer) return;

    setState(() => _printing = true);

    try {
      final printerService = ref.read(printerServiceProvider);
      await printerService.init();

      // Print internal receipt first — one per main work item
      if (_printInternal) {
        final receiptService = ref.read(receiptServiceProvider);
        final items =
            ref.read(orderWorkItemsProvider(widget.orderRef)).value ?? [];
        final mainItemIds = items
            .where((i) => !i.isExtra && !i.isGift)
            .map((i) => int.tryParse(i.id))
            .whereType<int>()
            .toList();

        bool anyInternalSuccess = false;
        for (final itemId in mainItemIds) {
          setState(() => _statusText = VN.fetchingInternalReceipt);
          final internalBytes = await receiptService.fetchReceipt(
            orderRef: widget.orderRef,
            type: ReceiptType.workTicket,
            itemId: itemId,
          );

          setState(() => _statusText = VN.printingInternalReceipt);
          final internalResult = await _tryPrint(
            printerService,
            internalBytes,
          );
          if (internalResult == PrinterPickerResult.success) {
            anyInternalSuccess = true;
          } else if (internalResult == PrinterPickerResult.failed) {
            setState(() => _printing = false);
            return;
          }
        }

        if (anyInternalSuccess) {
          final orderService = ref.read(orderServiceProvider);
          await orderService.updateWorkTicketPrintedAt(
            widget.orderRef,
            DateTime.now().toIso8601String(),
          );
          if (mounted) {
            showTopSnackBar(context, VN.internalReceiptPrinted);
          }
        }
      }

      // Print customer receipt
      if (_printCustomer) {
        setState(() => _statusText = VN.fetchingCustomerReceipt);
        final receiptService = ref.read(receiptServiceProvider);
        final customerBytes = await receiptService.fetchReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.customer,
        );

        setState(() => _statusText = VN.printingCustomerReceipt);
        await _tryPrint(printerService, customerBytes);
      }

      if (mounted) {
        showTopSnackBar(context, VN.printSuccess);
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

  Future<PrinterPickerResult> _tryPrint(
    PrinterService printerService,
    Uint8List imageBytes,
  ) async {
    // Try auto-reconnect to last printer first
    if (printerService.lastPrinterMac != null) {
      try {
        await printerService.connect(printerService.lastPrinterMac!);
        await printerService.printImage(imageBytes);
        return PrinterPickerResult.success;
      } catch (_) {
        // Fall through to picker
      }
    }

    if (!mounted) return PrinterPickerResult.cancelled;

    final result = await showPrinterPickerDialog(
      context: context,
      imageBytes: imageBytes,
      printerService: printerService,
    );

    if (!mounted) return PrinterPickerResult.cancelled;

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _printInternal || _printCustomer;

    return AlertDialog(
      title: Text(VN.printChecklistTitle),
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
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  value: _printInternal,
                  onChanged: (v) => setState(() => _printInternal = v ?? false),
                  title: Text(VN.printWorkTicket),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: _printCustomer,
                  onChanged: (v) => setState(() => _printCustomer = v ?? false),
                  title: Text(VN.printCustomerReceipt),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _printing ? null : () => Navigator.pop(context),
          child: Text(VN.printSkip),
        ),
        if (!_printing)
          FilledButton(
            onPressed: hasSelection ? _printSelected : null,
            child: Text(VN.print),
          ),
      ],
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
      final printerService = ref.read(printerServiceProvider);
      await printerService.init();

      final receiptService = ref.read(receiptServiceProvider);

      // Determine which items to print
      List<int> itemIds;
      if (widget.itemId != null) {
        itemIds = [widget.itemId!];
      } else {
        // Print all main (non-extra, non-gift) items
        final items =
            ref.read(orderWorkItemsProvider(widget.orderRef)).value ?? [];
        itemIds = items
            .where((i) => !i.isExtra && !i.isGift)
            .map((i) => int.tryParse(i.id))
            .whereType<int>()
            .toList();
      }

      if (itemIds.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      bool anySuccess = false;
      for (final id in itemIds) {
        setState(() => _statusText = VN.fetchingInternalReceipt);
        final internalBytes = await receiptService.fetchReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.workTicket,
          itemId: id,
        );

        setState(() => _statusText = VN.printingInternalReceipt);

        // Try auto-reconnect to last printer first
        PrinterPickerResult result = PrinterPickerResult.cancelled;
        if (printerService.lastPrinterMac != null) {
          try {
            await printerService.connect(printerService.lastPrinterMac!);
            await printerService.printImage(internalBytes);
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
          anySuccess = true;
        }
      }

      if (anySuccess) {
        final orderService = ref.read(orderServiceProvider);
        await orderService.updateWorkTicketPrintedAt(
          widget.orderRef,
          DateTime.now().toIso8601String(),
        );
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
      title: Text(VN.printChecklistTitle),
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
          : Text(VN.printInternalPrompt),
      actions: [
        TextButton(
          onPressed: _printing ? null : () => Navigator.pop(context),
          child: Text(VN.printSkip),
        ),
        if (!_printing)
          FilledButton(
            onPressed: _printInternal,
            child: Text(VN.print),
          ),
      ],
    );
  }
}
