import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/order_service.dart';
import '../../providers/pos_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

/// POS checkout confirmation screen.
/// Shows cart summary with 3 actions: Trở lại, Tiền mặt, Chuyển khoản.
class PosCheckoutScreen extends ConsumerStatefulWidget {
  const PosCheckoutScreen({super.key});

  @override
  ConsumerState<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends ConsumerState<PosCheckoutScreen> {
  bool _isProcessing = false;
  bool _navigatingAfterCheckout = false;

  Future<void> _createOrder(String paymentMethod) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final cart = ref.read(posCartProvider);
      final orderItems = cart.items
          .where((i) => !i.isGift)
          .map((i) => {
            'productId': i.product.id.toString(),
            'productName': i.product.name,
            'quantity': i.quantity,
            'unitPrice': i.product.basePrice,
          })
          .toList();

      final giftItems = cart.items
          .where((i) => i.isGift)
          .map((i) => {
            'productName': i.product.name,
            'quantity': i.quantity,
            'unitPrice': i.product.basePrice,
            'isGift': true,
          })
          .toList();

      orderItems.addAll(giftItems);

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: VN.khachLe,
        source: VN.taiTiem,
        deliveryType: 'pickup',
        items: orderItems,
        status: 'completed',
        paymentMethod: paymentMethod,
      );

      ref.read(posCartProvider.notifier).clearCart();

      if (!mounted) return;

      // Mark so build() doesn't redirect while we're navigating
      _navigatingAfterCheckout = true;

      if (paymentMethod == 'cash') {
        // Cash → show receipt/print screen
        context.pushReplacement('/pos/receipt/${order.orderRef}');
      } else {
        // Transfer → done (Phase 2 handles transfer proof upload)
        showTopSnackBar(context, VN.thanhToanThanhCong);
        context.go('/pos');
      }
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
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
      ),
      body: Column(
        children: [
          // Order summary
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: cart.items.length,
              itemBuilder: (context, i) {
                final item = cart.items[i];
                return ListTile(
                  leading: item.isGift
                      ? const Text('🎁', style: TextStyle(fontSize: 24))
                      : Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${item.quantity}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                  title: Text(
                    item.isGift
                        ? '${item.product.name} (Quà tặng)'
                        : item.product.name,
                    style: item.isGift
                        ? theme.textTheme.bodyMedium
                            ?.copyWith(fontStyle: FontStyle.italic)
                        : null,
                  ),
                  trailing: item.isGift
                      ? null
                      : Text(
                          formatVND(item.total),
                          style: theme.textTheme.titleSmall,
                        ),
                );
              },
            ),
          ),

          // Total
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
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

                // 3 action buttons
                Row(
                  children: [
                    // Trở lại
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Trở lại'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tiền mặt
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            _isProcessing ? null : () => _createOrder('cash'),
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.money),
                        label: Text(VN.tienMat),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Chuyển khoản
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            _isProcessing ? null : () => _createOrder('transfer'),
                        icon: const Icon(Icons.qr_code),
                        label: Text(VN.chuyenKhoan),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
