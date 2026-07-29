import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import '../../../../data/api/order_service.dart';
import '../../../../data/models/enum_attribute.dart';
import '../../../../data/models/order.dart';
import '../../../../data/models/payment_transaction.dart';
import '../../../../data/models/product.dart';
import '../../../../providers/order_providers.dart';
import '../../../../providers/products_provider.dart';
import '../../../../providers/events_provider.dart';
import 'package:bakery_app/shared/utils/api_error.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import '../order_photo_section.dart';
import '../rut_tien_section.dart';
import 'order_detail_helpers.dart';
import 'order_edit_payment_sheet.dart';
import 'order_info_block.dart';
import 'order_items_list.dart';
import 'order_payment_history.dart';
import 'order_payment_summary.dart';
import 'order_print_checklist_dialog.dart';
import 'order_print_status_row.dart';
import 'order_record_payment_sheet.dart';
import 'order_status_actions.dart';
import 'order_status_banner.dart';
import 'order_transaction_detail_sheet.dart';
import 'order_work_item_section.dart';

/// Body of the order detail screen — coordinates the order information,
/// payment summary, work items, photos, and status transition actions.
///
/// Extracted from the monolithic `order_detail_screen.dart` (DG-308 Phase 4.2
/// / FR-FL-1). Owns the transitioning state and print/sheet launch helpers.
class OrderDetailBody extends ConsumerStatefulWidget {
  const OrderDetailBody({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<OrderDetailBody> createState() => _OrderDetailBodyState();
}

class _OrderDetailBodyState extends ConsumerState<OrderDetailBody> {
  bool _transitioning = false;
  bool _acknowledgedOnce = false;

  Order get order => widget.order;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _acknowledgeIfNeeded();
    });
  }

  Future<void> _acknowledgeIfNeeded() async {
    if (_acknowledgedOnce) return;
    if (order.acknowledgedAt != null) return;
    _acknowledgedOnce = true;
    try {
      final service = ref.read(orderServiceProvider);
      await service.acknowledgeOrder(order.orderRef);
    } catch (e) {
      debugPrint('order_detail: acknowledge failed for ${order.orderRef}: $e');
    }
  }

  String _formatDueDisplay(String? date, String? time) {
    if (date == null) return '—';
    final d = parseApiDate(date);
    if (d == null) return time != null ? '$date $time' : date;
    final dateStr = formatDisplayDate(d);
    return time != null ? '$dateStr $time' : dateStr;
  }

  Future<void> _onTransition(String targetStatus) async {
    String reason = '';
    if (isBackward(order.status, targetStatus, orderStatusRank) ||
        targetStatus == 'cancelled') {
      final r = await showReasonDialog(context, targetStatus);
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
      final normalized = normalizeApiError(e);
      final statusCode = normalized.statusCode ?? 0;
      final backendDetail = normalized.message;
      if (statusCode == 422) {
        final action = orderStatusRecoveryActionFromDetail(backendDetail);
        final message = buildOrderStatusFailureMessage(
          reason: backendDetail,
          action: action,
          orderRef: order.orderRef,
          statusCode: statusCode,
        );
        if (kDebugMode) {
          debugPrint(
            '[order-status-transition-failed] orderRef=${order.orderRef} currentStatus=${order.status} targetStatus=$targetStatus httpStatus=$statusCode backendDetail=$backendDetail',
          );
        }
        if (mounted) {
          showTopSnackBar(context, message);
        }
        return;
      }
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: ${normalized.message}');
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _showPrintChecklistDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OrderPrintChecklistDialog(orderRef: order.orderRef),
    );
  }

  Future<void> _openAddPaymentSheet(double remaining) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          OrderRecordPaymentSheet(orderRef: order.orderRef, remaining: remaining),
    );
  }

  Future<void> _onMarkAsPrinted() async {
    try {
      final service = ref.read(orderServiceProvider);
      final changedBy = ref.read(loggedByProvider);
      await service.updateWorkTicketPrintedAt(
        order.orderRef,
        timestampToJson(DateTime.now()) ??
            DateTime.now().toUtc().toIso8601String(),
        changedBy: changedBy,
      );
      ref.invalidate(orderDetailProvider(order.orderRef));
      ref.invalidate(orderListProvider);
      if (mounted) {
        showTopSnackBar(context, VN.internalReceiptPrinted);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    }
  }

  Future<void> _onUnmarkPrinted() async {
    try {
      final service = ref.read(orderServiceProvider);
      final changedBy = ref.read(loggedByProvider);
      await service.updateWorkTicketPrintedAt(
        order.orderRef,
        '',
        changedBy: changedBy,
      );
      ref.invalidate(orderDetailProvider(order.orderRef));
      ref.invalidate(orderListProvider);
      if (mounted) {
        showTopSnackBar(context, VN.printStatusUnprinted);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    }
  }

  Future<void> _openTransactionDetail(PaymentTransaction txn) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OrderTransactionDetailSheet(
        txn: txn,
        orderRef: order.orderRef,
        onEdit: () => _openEditPaymentSheet(txn),
      ),
    );
  }

  Future<void> _openEditPaymentSheet(PaymentTransaction txn) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          OrderEditPaymentSheet(orderRef: order.orderRef, txn: txn),
    );
  }

  // Cached product list for enum-attribute label lookups during this build.
  List<Product> _products = const [];

  List<EnumAttribute> _enumAttributesFor(String productId) {
    if (productId.isEmpty || _products.isEmpty) return const [];
    for (final p in _products) {
      if (p.id.toString() == productId || p.productCode == productId) {
        return p.enumAttributes;
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forwardTransitions = validTransitions[order.status] ?? [];
    final currentRank = orderStatusRank[order.status] ?? 0;
    final backwardTransitions = orderStatusRank.entries
        .where((e) => e.value < currentRank && e.key != order.status)
        .map((e) => e.key)
        .toList();
    final transitions = [...forwardTransitions, ...backwardTransitions];

    _products = ref.watch(productsProvider).asData?.value ?? const [];

    final txnsAsync = ref.watch(
      orderPaymentTransactionsProvider(order.orderRef),
    );
    final txns = txnsAsync.value ?? [];
    final amountPaid =
        txnsAsync.hasValue ? computePaid(txns) : order.amountPaid;
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
        OrderStatusBanner(order: order),
        const SizedBox(height: 16),
        OrderPrintStatusRow(
          printedAt: order.workTicketPrintedAt,
          onMarkPrinted: _onMarkAsPrinted,
          onUnmarkPrinted: _onUnmarkPrinted,
        ),
        OrderInfoBlock(order: order, formatDueDisplay: _formatDueDisplay),
        const SizedBox(height: 16),
        OrderItemsList(order: order, enumAttributesFor: _enumAttributesFor),
        OrderPaymentSummary(
          order: order,
          amountPaid: amountPaid,
          remaining: remaining,
          paymentColor: paymentColor,
          paymentLabel: paymentLabel,
          onAddPayment: () => _openAddPaymentSheet(remaining),
        ),
        const SizedBox(height: 16),
        OrderWorkItemSection(orderRef: order.orderRef, order: order),
        const SizedBox(height: 16),
        RutTienSection(
          orderRef: order.orderRef,
          onRecordPayment: _openAddPaymentSheet,
        ),
        const SizedBox(height: 16),
        OrderPaymentHistory(
          txns: txns,
          onTransactionTap: _openTransactionDetail,
        ),
        const SizedBox(height: 16),
        OrderPhotoSection(
          orderRef: order.orderRef,
          baseUrl: ref.watch(apiBaseUrlProvider),
        ),
        OrderStatusActions(
          transitions: transitions,
          backwardTransitions: backwardTransitions,
          remaining: remaining,
          transitioning: _transitioning,
          onTransition: _onTransition,
        ),
      ],
    );
  }
}