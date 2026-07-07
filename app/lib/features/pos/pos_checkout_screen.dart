import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/order_service.dart';
import '../../features/orders/widgets/order_wizard.dart';
import '../../features/orders/widgets/section_header.dart';
import '../../features/pos/utils/pos_cart_item_display.dart';
import '../../features/pos/widgets/pos_checkout_cart_item_tile.dart';
import '../../features/pos/widgets/pos_checkout_dialogs.dart';
import '../../features/stock/stock_screen.dart';
import '../../providers/pos_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/labels/orders.dart';
import '../../shared/utils/api_error.dart' as api_error;
import '../../shared/utils/date_formatting.dart';
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

  late OrderWizardData _wizardData;

  @override
  void initState() {
    super.initState();
    _wizardData = OrderWizardData();
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
      final orderItems = _buildOrderItems();
      final dueDate = posCheckoutLocalDueDate(DateTime.now());
      final isDelivery = _wizardData.deliveryType == 'bus' || _wizardData.deliveryType == 'door';
      final status = isDelivery ? 'new' : 'delivered';

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: _wizardData.customerName.isNotEmpty
            ? _wizardData.customerName
            : VN.khachLe,
        customerPhone: _wizardData.customerPhone,
        customerId: _wizardData.selectedCustomer?.id,
        source: VN.taiTiemPOS,
        dueDate: dueDate,
        deliveryType: _wizardData.deliveryType,
        deliveryAddress: _wizardData.deliveryAddress,
        shippingFee: _wizardData.shippingFee,
        notes: _wizardData.notes,
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

      final orderItems = _buildOrderItems();
      final dueDate = posCheckoutLocalDueDate(DateTime.now());
      final isDelivery = _wizardData.deliveryType == 'bus' || _wizardData.deliveryType == 'door';
      final status = isDelivery ? 'new' : 'delivered';

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: _wizardData.customerName.isNotEmpty
            ? _wizardData.customerName
            : VN.khachLe,
        customerPhone: _wizardData.customerPhone,
        customerId: _wizardData.selectedCustomer?.id,
        source: VN.taiTiemPOS,
        dueDate: dueDate,
        deliveryType: _wizardData.deliveryType,
        deliveryAddress: _wizardData.deliveryAddress,
        shippingFee: _wizardData.shippingFee,
        notes: _wizardData.notes,
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
          Expanded(
            child: OrderWizard(
              data: _wizardData,
              onDataChanged: () => setState(() {}),
              onFinalize: _handleFinalizeOrder,
              showCustomerStep: true,
              showDeliveryStep: true,
              showReviewStep: true,
              skipCustomerIfWalkIn: false,
              skipDeliveryIfPickup: true,
              isProcessing: _isProcessing,
              extraReviewWidgets: [
                _buildCartReview(),
                _buildPaymentReview(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartReview() {
    final cart = ref.watch(posCartProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    );
  }

  Widget _buildPaymentReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
    );
  }
}
