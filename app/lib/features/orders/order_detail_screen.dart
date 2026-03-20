import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/api/api_client.dart';
import '../../data/models/order.dart';
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

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderRef});

  final String orderRef;

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
    if (targetStatus == 'cancelled') {
      await _showCancelDialog();
      return;
    }
    setState(() => _transitioning = true);
    try {
      await ref
          .read(orderDetailProvider(order.orderRef).notifier)
          .transitionTo(targetStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VN.orderStatusUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${VN.apiError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _showCancelDialog() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.cancelOrderTitle),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: VN.cancelReasonLabel,
            hintText: VN.cancelReasonHint,
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(VN.confirmCancelAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _transitioning = true);
    try {
      await ref
          .read(orderDetailProvider(order.orderRef).notifier)
          .transitionTo('cancelled', reason: reasonCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VN.orderStatusUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${VN.apiError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;
    final transitions = validTransitions[order.status] ?? [];

    final remaining = order.totalPrice - order.amountPaid;
    final paymentColor = order.isPaid
        ? Colors.green
        : order.amountPaid > 0
            ? Colors.orange
            : theme.colorScheme.error;
    final paymentLabel = order.isPaid
        ? VN.paid
        : order.amountPaid > 0
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
                value: formatVND(order.amountPaid),
                valueStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: order.amountPaid > 0 ? Colors.green : null,
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

        // ── Photos ────────────────────────────────────────────────────
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
                return isCancel
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                        ),
                        onPressed: () => _onTransition(t),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: Text(statusActionLabel(t)),
                      )
                    : FilledButton.icon(
                        onPressed: () => _onTransition(t),
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
