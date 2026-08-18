import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/order_service.dart';
import '../../data/models/order.dart';
import '../../data/models/payment_transaction.dart';
import '../../providers/order_providers.dart';
import '../../shared/providers/logged_by_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/templates.dart';
import 'package:bakery_app/shared/utils/api_error.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/utils/order_helpers.dart';
import 'package:bakery_app/shared/utils/order_photo_tags.dart';
import 'package:bakery_app/shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/data/api/api_client.dart' show apiBaseUrlProvider;
import '../templates/template_context.dart';
import '../templates/widgets/template_picker_modal.dart';
import 'providers/delivery_claim_handler.dart';
import 'providers/delivery_claim_providers.dart';
import 'widgets/google_maps_modal.dart';
import 'widgets/order_detail/order_detail_customer_tab.dart';
import 'widgets/order_detail/order_detail_general_tab.dart';
import 'widgets/order_detail/order_detail_helpers.dart';
import 'widgets/order_detail/order_detail_transactions_tab.dart';
import 'widgets/order_detail/order_detail_work_items_tab.dart';
import 'widgets/order_detail/order_edit_payment_sheet.dart';
import 'widgets/order_detail/order_print_checklist_dialog.dart';
import 'widgets/order_detail/order_record_payment_sheet.dart';
import 'widgets/order_detail/order_receipt_type_selector.dart';
import 'widgets/order_detail/order_status_actions.dart';
import 'widgets/order_detail/order_status_banner.dart';
import 'widgets/order_detail/order_transaction_detail_sheet.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderRef});

  final String orderRef;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 4;
  late final TabController _tabController;
  bool _transitioning = false;
  bool _acknowledgedOnce = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _acknowledgeIfNeeded();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Order? get _order =>
      ref.read(orderDetailProvider(widget.orderRef)).asData?.value;

  Future<void> _acknowledgeIfNeeded() async {
    if (_acknowledgedOnce) return;
    final order = _order;
    if (order == null || order.acknowledgedAt != null) return;
    _acknowledgedOnce = true;
    try {
      final service = ref.read(orderServiceProvider);
      await service.acknowledgeOrder(order.orderRef);
    } catch (e) {
      debugPrint('order_detail: acknowledge failed for ${order.orderRef}: $e');
    }
  }

  Future<void> _onTransition(String targetStatus) async {
    final order = _order;
    if (order == null) return;
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
      ref.read(orderWorkItemsProvider(order.orderRef).notifier).refresh();
      if (mounted) {
        showTopSnackBar(context, VN.orderStatusUpdated);
      }
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
      builder: (ctx) => OrderPrintChecklistDialog(orderRef: widget.orderRef),
    );
  }

  Future<void> _openAddPaymentSheet(double remaining) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OrderRecordPaymentSheet(
        orderRef: widget.orderRef,
        remaining: remaining,
      ),
    );
  }

  Future<void> _onMarkAsPrinted() async {
    try {
      final service = ref.read(orderServiceProvider);
      final changedBy = ref.read(loggedByProvider);
      await service.updateWorkTicketPrintedAt(
        widget.orderRef,
        timestampToJson(DateTime.now()) ??
            DateTime.now().toUtc().toIso8601String(),
        changedBy: changedBy,
      );
      ref.invalidate(orderDetailProvider(widget.orderRef));
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
        widget.orderRef,
        '',
        changedBy: changedBy,
      );
      ref.invalidate(orderDetailProvider(widget.orderRef));
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
        orderRef: widget.orderRef,
        onEdit: () => _openEditPaymentSheet(txn),
      ),
    );
  }

  Future<void> _openEditPaymentSheet(PaymentTransaction txn) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          OrderEditPaymentSheet(orderRef: widget.orderRef, txn: txn),
    );
  }

  List<PopupMenuEntry<String>> buildMenuItems(
    Order? order,
    CurrentStaff? staff,
    bool isClaiming,
  ) {
    final items = <PopupMenuEntry<String>>[];

    if (order != null) {
      items.addAll([
        const PopupMenuItem<String>(
          value: 'addIncident',
          child: Text(VN.addOrderIncident),
        ),
        const PopupMenuItem<String>(
          value: 'googleMaps',
          child: Text(OrdersLabels.googleMapsContextMenuLabel),
        ),
        const PopupMenuItem<String>(
          value: 'messageTemplates',
          child: Text(TemplatesLabels.overflowMenuOpenPicker),
        ),
      ]);

      if (staff != null &&
          staff.canClaim &&
          isDeliveryType(order.deliveryType) &&
          activeOrderStatuses.contains(order.status)) {
        if (order.isAssigned) {
          if (staff.isAdmin || order.isClaimedBy(staff.staffIdAsString)) {
            items.add(const PopupMenuItem<String>(
              value: 'unclaim',
              child: Text(OrdersLabels.deliveryUnclaimButton),
            ));
          }
        } else {
          items.add(PopupMenuItem<String>(
            value: 'claim',
            enabled: !isClaiming,
            child: const Text(OrdersLabels.deliveryClaimButton),
          ));
        }
      }
    }

    return items;
  }

  Future<void> _handleClaimMenuSelection(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) =>
      handleDeliveryClaimAction(
        context,
        ref,
        widget.orderRef,
        isClaim: value == 'claim',
      );

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderDetailProvider(widget.orderRef));
    final staffAsync = ref.watch(currentStaffProvider);
    final claimAsync = ref.watch(orderClaimProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.orderDetail),
        actions: [
          if (orderAsync.asData != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: VN.editOrder,
              onPressed: () async {
                await context.push('/orders/${widget.orderRef}/edit');
                ref
                    .read(orderDetailProvider(widget.orderRef).notifier)
                    .refresh();
              },
            ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: VN.printReceipt,
            onPressed: () => showOrderReceiptTypeSelector(
              context,
              ref,
              widget.orderRef,
            ),
          ),
          AppBarOverflowMenu(
            items: buildMenuItems(
              orderAsync.asData?.value,
              staffAsync.asData?.value,
              claimAsync.isLoading,
            ),
            onSelected: (value) {
              if (value == 'addIncident') {
                final order = orderAsync.asData!.value;
                final orderId = int.tryParse(order.id);
                context.push(
                  '/orders/${widget.orderRef}/incident/new',
                  extra: orderId,
                );
              } else if (value == 'googleMaps') {
                final order = orderAsync.asData!.value;
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => GoogleMapsModal(
                    orderRef: order.orderRef,
                    initialUrl: order.googleMapsUrl,
                  ),
                );
              } else if (value == 'messageTemplates') {
                final order = orderAsync.asData!.value;
                TemplatePickerModal.show(
                  context,
                  templateContext: TemplateContext.fromOrder(order),
                );
              } else if (value == 'claim' || value == 'unclaim') {
                _handleClaimMenuSelection(context, ref, value);
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: VN.orderDetailTabGeneral),
            Tab(text: VN.orderDetailTabWorkItems),
            Tab(text: VN.orderDetailTabTransactions),
            Tab(text: VN.orderDetailTabCustomer),
          ],
        ),
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref
                    .read(orderDetailProvider(widget.orderRef).notifier)
                    .refresh(),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (order) {
          final theme = Theme.of(context);
          final forwardTransitions = validTransitions[order.status] ?? [];
          final currentRank = orderStatusRank[order.status] ?? 0;
          final backwardTransitions = orderStatusRank.entries
              .where((e) => e.value < currentRank && e.key != order.status)
              .map((e) => e.key)
              .toList();
          final transitions = [...forwardTransitions, ...backwardTransitions];

          final txnsAsync = ref.watch(
            orderPaymentTransactionsProvider(order.orderRef),
          );
          final txns = txnsAsync.value ?? [];
          final amountPaid =
              txnsAsync.hasValue ? computePaid(txns) : order.amountPaid;
          final remaining = order.totalPrice - amountPaid;
          // NFR1: parent fetches order photos once and forwards the
          // chuyen-khoan tagged subset to the Transactions tab — no extra
          // network fetch on tab switch (DG-364 Phase 4.2 / FR1 / AC1).
          final photosAsync = ref.watch(orderPhotosProvider(order.orderRef));
          final transferPhotos = (photosAsync.value ?? const [])
              .where((p) => parseOrderPhotoTags(p.tags).contains('chuyen-khoan'))
              .toList();
          final baseUrl = ref.watch(apiBaseUrlProvider);
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

          return Column(
            children: [
              // Persistent status banner — visible above all tabs (FR3 / AC3).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OrderStatusBanner(order: order),
              ),
              // Tab content fills the remaining space.
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    OrderDetailGeneralTab(
                      order: order,
                      amountPaid: amountPaid,
                      remaining: remaining,
                      paymentColor: paymentColor,
                      paymentLabel: paymentLabel,
                      onAddPayment: () => _openAddPaymentSheet(remaining),
                      onMarkAsPrinted: _onMarkAsPrinted,
                      onUnmarkPrinted: _onUnmarkPrinted,
                    ),
                    OrderDetailWorkItemsTab(
                      order: order,
                      onRecordPayment: _openAddPaymentSheet,
                    ),
                    OrderDetailTransactionsTab(
                      order: order,
                      amountPaid: amountPaid,
                      remaining: remaining,
                      txns: txns,
                      onAddPayment: () => _openAddPaymentSheet(remaining),
                      onTransactionTap: _openTransactionDetail,
                      transferPhotos: transferPhotos,
                      baseUrl: baseUrl,
                    ),
                    OrderDetailCustomerTab(customerId: order.customerId),
                  ],
                ),
              ),
              // Persistent status action buttons — visible below all tabs
              // (FR7 / AC3).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: OrderStatusActions(
                  transitions: transitions,
                  backwardTransitions: backwardTransitions,
                  remaining: remaining,
                  transitioning: _transitioning,
                  onTransition: _onTransition,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}