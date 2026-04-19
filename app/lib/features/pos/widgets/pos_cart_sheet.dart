import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/order_service.dart';
import '../../../providers/pos_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

/// Expandable cart detail bottom sheet for POS.
class PosCartSheet extends ConsumerStatefulWidget {
  const PosCartSheet({super.key});

  @override
  ConsumerState<PosCartSheet> createState() => _PosCartSheetState();
}

class _PosCartSheetState extends ConsumerState<PosCartSheet> {
  bool _isProcessing = false;

  Future<void> _checkout() async {
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

      // Add gift items with actual price and isGift flag
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
        paymentMethod: 'cash',
      );

      // Clear cart
      ref.read(posCartProvider.notifier).clearCart();

      if (!mounted) return;

      // Close cart sheet
      Navigator.pop(context);

      // Navigate to POS receipt screen
      context.push('/pos/receipt/${order.orderRef}');
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

    if (cart.items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 48),
            const SizedBox(height: 8),
            const Text('Giỏ hàng trống'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Giỏ hàng',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _confirmClearCart(context, ref),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Xóa giỏ'),
                  ),
                ],
              ),
            ),

            const Divider(),

            // Cart items list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: cart.items.length,
                itemBuilder: (context, i) {
                  final item = cart.items[i];
                  return _CartItemTile(item: item);
                },
              ),
            ),

            // Footer with total + checkout button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(25),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          VN.total,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          formatVND(cart.total),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isProcessing ? null : _checkout,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.payment),
                        label: Text(
                          _isProcessing ? 'Đang xử lý...' : VN.thanhToan,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmClearCart(BuildContext context, WidgetRef ref) {
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
              Navigator.pop(context);
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  const _CartItemTile({required this.item});

  final PosCartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey('${item.product.id}-${item.isGift}'),
      direction: item.isGift ? DismissDirection.none : DismissDirection.endToStart,
      onDismissed: (_) {
        if (!item.isGift) {
          ref.read(posCartProvider.notifier).removeItem(item.product.id);
        }
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: theme.colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
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
          item.isGift ? '${item.product.name} (Quà tặng)' : item.product.name,
          style: item.isGift
              ? theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)
              : null,
        ),
        subtitle: item.isGift
            ? null
            : Text(formatVND(item.product.basePrice)),
        trailing: item.isGift
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: () {
                      ref.read(posCartProvider.notifier).updateQuantity(
                        item.product.id,
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
                      ref.read(posCartProvider.notifier).updateQuantity(
                        item.product.id,
                        item.quantity + 1,
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
