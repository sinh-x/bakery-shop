import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/order_service.dart';
import '../../features/pos/utils/pos_cart_item_display.dart';
import '../../features/pos/widgets/pos_checkout_cart_item_tile.dart';
import '../../features/pos/widgets/pos_checkout_dialogs.dart';
import '../../features/pos/widgets/pos_checkout_edit_panel.dart';
import '../../features/stock/stock_screen.dart';
import '../../features/pos/widgets/pos_checkout_review_panel.dart';
import '../../providers/pos_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/labels/orders.dart';
import '../../shared/utils/api_error.dart' as api_error;
import '../../shared/widgets/app_bar_overflow_menu.dart';

String posCheckoutLocalDueDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

@visibleForTesting
String resolvePosCheckoutErrorMessage(Object error) {
  return api_error.normalizeApiError(error).message;
}

@visibleForTesting
String? extractBackendDetail(Object? data) {
  return api_error.extractBackendDetail(data);
}

/// POS checkout screen — editable cart on checkout, single Thanh toán button.
class PosCheckoutScreen extends ConsumerStatefulWidget {
  const PosCheckoutScreen({super.key});

  @override
  ConsumerState<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends ConsumerState<PosCheckoutScreen> {
  bool _isProcessing = false;
  bool _navigatingAfterCheckout = false;
  bool _isReviewStep = false;
  String _selectedPaymentMethod = 'cash'; // 'cash' or 'transfer'

  void _onPaymentMethodChanged(String paymentMethod) {
    if (_selectedPaymentMethod == paymentMethod) {
      return;
    }
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
      };
    }).toList();

    final giftItems = cart.items
        .where((i) => i.isGift)
        .map(
          (i) => <String, dynamic>{
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

  void _openReviewStep() {
    if (_isProcessing) return;
    setState(() => _isReviewStep = true);
  }

  void _backToEditStep() {
    if (_isProcessing) return;
    setState(() => _isReviewStep = false);
  }

  String _paymentMethodLabel() {
    return _selectedPaymentMethod == 'transfer' ? VN.chuyenKhoan : VN.tienMat;
  }

  Future<void> _createOrder(String paymentMethod) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final orderItems = _buildOrderItems();
      final dueDate = posCheckoutLocalDueDate(DateTime.now());

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: VN.khachLe,
        source: VN.taiTiemPOS,
        dueDate: dueDate,
        deliveryType: 'pickup',
        items: orderItems,
        status: 'delivered',
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

    // Ask: camera, gallery, or skip?
    final source = await showTransferSourceDialog(context);

    if (source == null) return; // cancelled

    // "Bỏ qua" — create order without photo
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

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: VN.khachLe,
        source: VN.taiTiemPOS,
        dueDate: dueDate,
        deliveryType: 'pickup',
        items: orderItems,
        status: 'delivered',
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
        title: Text(
          _isReviewStep ? OrdersLabels.checkoutReviewTitle : VN.thanhToan,
        ),
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
          // Editable item list
          if (_isReviewStep)
            Expanded(
              child: PosCheckoutReviewPanel(
                items: cart.items,
                total: cart.total,
                paymentMethodLabel: _paymentMethodLabel(),
                isProcessing: _isProcessing,
                onEditOrder: _backToEditStep,
                onFinalize: _handleFinalizeOrder,
              ),
            )
          else ...[
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: cart.items.length,
                itemBuilder: (context, i) {
                  final item = cart.items[i];
                  return PosCheckoutCartItemTile(item: item);
                },
              ),
            ),
            PosCheckoutEditPanel(
              total: cart.total,
              selectedPaymentMethod: _selectedPaymentMethod,
              isProcessing: _isProcessing,
              onPaymentMethodChanged: _onPaymentMethodChanged,
              onOpenReview: _openReviewStep,
            ),
          ],
        ],
      ),
    );
  }
}
