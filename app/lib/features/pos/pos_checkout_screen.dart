import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/order_service.dart';
import '../../features/stock/stock_screen.dart';
import '../../providers/pos_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

/// POS checkout screen — editable cart on checkout, single Thanh toán button.
class PosCheckoutScreen extends ConsumerStatefulWidget {
  const PosCheckoutScreen({super.key});

  @override
  ConsumerState<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends ConsumerState<PosCheckoutScreen> {
  bool _isProcessing = false;
  bool _navigatingAfterCheckout = false;
  String _selectedPaymentMethod = 'cash'; // 'cash' or 'transfer'

  List<Map<String, dynamic>> _buildOrderItems() {
    final cart = ref.read(posCartProvider);
    final orderItems = cart.items
        .where((i) => !i.isGift)
        .map((i) {
          final hasChipLabel = (i.selectedChipLabel ?? '').trim().isNotEmpty;
          final productName = hasChipLabel
              ? '${i.product.name} (${i.selectedChipLabel!.trim()})'
              : i.product.name;

          return <String, dynamic>{
            'productId': i.product.id.toString(),
            'productName': productName,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'priceChipId': i.selectedChipId,
          };
        })
        .toList();

    final giftItems = cart.items
        .where((i) => i.isGift)
        .map((i) => <String, dynamic>{
              'productName': i.product.name,
              'quantity': i.quantity,
              'unitPrice': i.product.basePrice,
              'isGift': true,
            })
        .toList();

    orderItems.addAll(giftItems);
    return orderItems;
  }

  Future<void> _handleThanhToan() async {
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

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: VN.khachLe,
        source: VN.taiTiemPOS,
        deliveryType: 'pickup',
        items: orderItems,
        status: 'delivered',
        paymentMethod: paymentMethod,
      );

      ref.read(posCartProvider.notifier).clearCart();
      ref.invalidate(productsProvider);
      ref.invalidate(stockOverviewProvider);

      if (!mounted) return;

      _navigatingAfterCheckout = true;
      context.pushReplacement('/pos/receipt/${order.orderRef}');
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleTransfer() async {
    if (_isProcessing) return;

    // Ask: camera, gallery, or skip?
    final source = await showDialog<Object>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Bằng chứng chuyển khoản'),
        content: const Text('Chọn nguồn ảnh để xác nhận thanh toán.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'skip'),
            child: const Text('Bỏ qua'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, ImageSource.camera),
            child: const Text('📷 Camera'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, ImageSource.gallery),
            child: const Text('🖼️ Thư viện'),
          ),
        ],
      ),
    );

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

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: VN.khachLe,
        source: VN.taiTiemPOS,
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

      ref.read(posCartProvider.notifier).clearCart();
      ref.invalidate(productsProvider);
      ref.invalidate(stockOverviewProvider);

      if (!mounted) return;
      _navigatingAfterCheckout = true;
      showTopSnackBar(context, VN.thanhToanThanhCong);
      context.pushReplacement('/pos/receipt/${order.orderRef}');
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _confirmClearCart() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Xóa giỏ hàng?'),
        content: const Text('Bạn có chắc muốn xóa tất cả sản phẩm trong giỏ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () {
              ref.read(posCartProvider.notifier).clearCart();
              Navigator.pop(dialogCtx);
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(posCartProvider);
    final theme = Theme.of(context);

    if (cart.items.isEmpty && !_navigatingAfterCheckout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/pos');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(VN.thanhToan),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _confirmClearCart,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Xóa giỏ'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Editable item list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: cart.items.length,
              itemBuilder: (context, i) {
                final item = cart.items[i];
                return _CheckoutCartItemTile(item: item);
              },
            ),
          ),

          // Footer: total + payment toggle + single Thanh toán button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  // Total row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        VN.total,
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        formatVND(cart.total),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Cash / Transfer segmented toggle
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
                    onSelectionChanged: (selection) {
                      setState(() => _selectedPaymentMethod = selection.first);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Single Thanh toán button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : _handleThanhToan,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.payment),
                      label: Text(VN.thanhToan),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editable cart item tile for checkout screen — swipe to delete, qty +/-, gift can swipe.
class _CheckoutCartItemTile extends ConsumerWidget {
  const _CheckoutCartItemTile({required this.item});

  final PosCartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey('${item.lineKey}-${item.isGift}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        ref.read(posCartProvider.notifier).removeItemByLineKey(item.lineKey);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ListTile(
          leading: item.isGift
              ? const Chip(label: Text('🎁'))
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cake,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
          title: Text(
            item.isGift
                ? '${item.product.name} (Quà tặng)'
                : item.selectedChipLabel != null
                ? '${item.product.name} (${item.selectedChipLabel})'
                : item.product.name,
            style: item.isGift
                ? theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  )
                : null,
          ),
          subtitle: item.isGift
              ? null
              : Text(formatVND(item.unitPrice)),
          trailing: item.isGift
              ? Icon(
                  Icons.chevron_left,
                  color: theme.colorScheme.outline,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: () {
                        ref.read(posCartProvider.notifier).updateQuantityByLineKey(
                              item.lineKey,
                              item.quantity - 1,
                            );
                      },
                    ),
                    Text(
                      '${item.quantity}',
                      style: theme.textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () {
                        ref.read(posCartProvider.notifier).updateQuantityByLineKey(
                              item.lineKey,
                              item.quantity + 1,
                            );
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
