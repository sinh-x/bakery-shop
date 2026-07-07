import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/order_service.dart';
import '../../features/orders/widgets/order_stage_indicator.dart';
import '../../features/orders/widgets/order_wizard.dart';
import '../../features/orders/widgets/section_header.dart';
import '../../features/orders/widgets/stage2_customer_info_screen.dart';
import '../../features/orders/widgets/stage3_delivery_options_screen.dart';
import '../../features/pos/utils/pos_cart_item_display.dart';
import '../../features/pos/widgets/pos_checkout_cart_item_tile.dart';
import '../../features/pos/widgets/pos_checkout_dialogs.dart';
import '../../features/stock/stock_screen.dart';
import '../../providers/order/order_create_state_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/labels/orders.dart';
import '../../shared/utils/api_error.dart' as api_error;
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/order_helpers.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';

String posCheckoutLocalDueDate(DateTime dateTime) {
  return formatApiDate(dateTime);
}

@visibleForTesting
String resolvePosCheckoutErrorMessage(Object error) {
  return api_error.normalizeApiError(error).message;
}

@visibleForTesting
String? extractBackendDetail(Object? data) {
  return api_error.extractBackendDetail(data);
}

class PosCheckoutScreen extends ConsumerStatefulWidget {
  const PosCheckoutScreen({super.key});

  @override
  ConsumerState<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends ConsumerState<PosCheckoutScreen> {
  bool _isProcessing = false;
  bool _navigatingAfterCheckout = false;
  String _selectedPaymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPosState();
    });
  }

  void _initPosState() {
    final notifier = ref.read(orderCreateStateProvider.notifier);
    final wizardData = OrderWizardData(
      customerName: VN.khachLe,
      source: VN.taiTiemPOS,
    );
    notifier.updateWizardData(wizardData);
    notifier.updateSource(VN.taiTiemPOS);
    notifier.goToStage(2);
  }

  void _goToStage(int stage) {
    ref.read(orderCreateStateProvider.notifier).goToStage(stage);
  }

  void _onStage2Continue() {
    final state = ref.read(orderCreateStateProvider);
    if (state.wizardData.deliveryType == 'pickup') {
      _goToStage(4);
    } else {
      _goToStage(3);
    }
  }

  void _onPaymentMethodChanged(String paymentMethod) {
    if (_selectedPaymentMethod == paymentMethod) return;
    setState(() => _selectedPaymentMethod = paymentMethod);
  }

  List<Map<String, dynamic>> _buildOrderItems() {
    final cart = ref.read(posCartProvider);
    final orderItems = cart.items.where((i) => !i.isGift).map((i) {
      return <String, dynamic>{
        'productId': i.product.id.toString(),
        'productName': posCartItemDisplayName(i),
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'priceChipId': i.selectedChipId,
        if (!i.useInventory) 'attributes': {'useInventory': 'false'},
      };
    }).toList();

    final giftItems = cart.items
        .where((i) => i.isGift)
        .map(
          (i) => <String, dynamic>{
            'productId': i.product.id.toString(),
            'productName': i.product.name,
            'quantity': i.quantity,
            'unitPrice': i.product.basePrice,
            'isGift': true,
          },
        )
        .toList();

    orderItems.addAll(giftItems);
    return orderItems;
  }

  Future<void> _handleFinalizeOrder() async {
    if (_isProcessing) return;

    if (_selectedPaymentMethod == 'transfer') {
      await _handleTransfer();
    } else {
      await _createOrder('cash');
    }
  }

  Future<void> _createOrder(String paymentMethod) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final state = ref.read(orderCreateStateProvider);
      final data = state.wizardData;
      final orderItems = _buildOrderItems();
      final dueDate = posCheckoutLocalDueDate(DateTime.now());
      final isDelivery = data.deliveryType == 'bus' || data.deliveryType == 'door';
      final status = isDelivery ? 'new' : 'delivered';

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: data.customerName.isNotEmpty
            ? data.customerName
            : VN.khachLe,
        customerPhone: data.customerPhone,
        customerId: data.selectedCustomer?.id,
        source: VN.taiTiemPOS,
        dueDate: dueDate,
        deliveryType: data.deliveryType,
        deliveryAddress: data.deliveryAddress,
        deliveryPhone: data.deliveryPhone,
        shippingFee: data.shippingFee,
        notes: data.notes,
        items: orderItems,
        status: status,
        paymentMethod: paymentMethod,
      );

      if (!mounted) return;

      _navigatingAfterCheckout = true;
      context.pushReplacement('/pos/receipt/${order.orderRef}');
      ref.read(posCartProvider.notifier).clearCart();
      ref.invalidate(productsProvider);
      ref.invalidate(stockOverviewProvider);
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, resolvePosCheckoutErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleTransfer() async {
    if (_isProcessing) return;

    final source = await showTransferSourceDialog(context);
    if (source == null) return;

    if (source == 'skip') {
      await _createOrder('transfer');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source as ImageSource,
        imageQuality: 85,
      );
      if (image == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final state = ref.read(orderCreateStateProvider);
      final data = state.wizardData;
      final orderItems = _buildOrderItems();
      final dueDate = posCheckoutLocalDueDate(DateTime.now());
      final isDelivery = data.deliveryType == 'bus' || data.deliveryType == 'door';
      final status = isDelivery ? 'new' : 'delivered';

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: data.customerName.isNotEmpty
            ? data.customerName
            : VN.khachLe,
        customerPhone: data.customerPhone,
        customerId: data.selectedCustomer?.id,
        source: VN.taiTiemPOS,
        dueDate: dueDate,
        deliveryType: data.deliveryType,
        deliveryAddress: data.deliveryAddress,
        deliveryPhone: data.deliveryPhone,
        shippingFee: data.shippingFee,
        notes: data.notes,
        items: orderItems,
        status: status,
        paymentMethod: 'transfer',
      );

      await orderService.uploadOrderPhoto(
        order.orderRef,
        image,
        tags: 'chuyen-khoan',
      );

      if (!mounted) return;
      _navigatingAfterCheckout = true;
      showTopSnackBar(context, VN.thanhToanThanhCong);
      context.pushReplacement('/pos/receipt/${order.orderRef}');
      ref.read(posCartProvider.notifier).clearCart();
      ref.invalidate(productsProvider);
      ref.invalidate(stockOverviewProvider);
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, resolvePosCheckoutErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _confirmClearCart() {
    showClearCartDialog(
      context: context,
      onConfirm: () {
        ref.read(posCartProvider.notifier).clearCart();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(posCartProvider);

    if (cart.items.isEmpty && !_navigatingAfterCheckout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/pos');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final state = ref.watch(orderCreateStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.thanhToan),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: VN.backToCart,
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _confirmClearCart,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text(VN.clearCart),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: OrderStageIndicator(currentStage: state.currentStage),
          ),
          Expanded(
            child: _buildCurrentStage(state),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStage(OrderCreateState state) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (state.currentStage) {
        2 => Stage2CustomerInfoScreen(
            key: const ValueKey('stage2'),
            posMode: true,
            onBack: () => context.pop(),
            onContinue: _onStage2Continue,
          ),
        3 => Stage3DeliveryOptionsScreen(
            key: const ValueKey('stage3'),
            onBack: () => _goToStage(2),
            onContinue: () => _goToStage(4),
          ),
        4 => _buildPosReviewStage(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildPosReviewStage() {
    final cart = ref.watch(posCartProvider);
    final state = ref.watch(orderCreateStateProvider);
    final data = state.wizardData;
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  OrdersLabels.checkoutReviewTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  OrdersLabels.checkoutReviewHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeader(OrdersLabels.stage2Label),
                _buildReviewRow(theme, VN.customerName, data.customerName.isNotEmpty ? data.customerName : '—'),
                if (data.customerPhone.isNotEmpty)
                  _buildReviewRow(theme, VN.customerPhone, data.customerPhone),
                const SizedBox(height: 16),
                const SectionHeader(OrdersLabels.stage3Label),
                _buildReviewRow(theme, VN.deliveryType, deliveryTypeLabel(data.deliveryType)),
                if (data.needsAddress) ...[
                  if (data.deliveryPhone.isNotEmpty)
                    _buildReviewRow(theme, OrdersLabels.deliveryPhone, data.deliveryPhone),
                  if (data.deliveryAddress.isNotEmpty)
                    _buildReviewRow(theme, VN.deliveryAddress, data.deliveryAddress),
                ],
                const SizedBox(height: 16),
                const SectionHeader(VN.products),
                ...cart.items.map(
                  (item) => PosCheckoutCartItemTile(item: item),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${VN.total}: ', style: theme.textTheme.bodyMedium),
                    Text(
                      formatVND(cart.total),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SectionHeader(VN.paymentMethod),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'cash',
                      label: Text(VN.tienMat),
                      icon: Icon(Icons.money),
                    ),
                    ButtonSegment(
                      value: 'transfer',
                      label: Text(VN.chuyenKhoan),
                      icon: Icon(Icons.qr_code),
                    ),
                  ],
                  selected: {_selectedPaymentMethod},
                  onSelectionChanged: (s) => _onPaymentMethodChanged(s.first),
                  showSelectedIcon: false,
                  multiSelectionEnabled: false,
                ),
              ],
            ),
          ),
        ),
        _buildReviewNavigation(),
      ],
    );
  }

  Widget _buildReviewRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
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

  Widget _buildReviewNavigation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: () => _goToStage(2),
            child: const Text(OrdersLabels.backLabel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _isProcessing ? null : _handleFinalizeOrder,
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(VN.submitOrder),
          ),
        ],
      ),
    );
  }
}
