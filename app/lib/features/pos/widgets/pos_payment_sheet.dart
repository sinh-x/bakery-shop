import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/api/order_service.dart';
import '../../../providers/pos_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

/// Payment confirmation sheet for POS counter sales.
class PosPaymentSheet extends ConsumerStatefulWidget {
  const PosPaymentSheet({super.key});

  @override
  ConsumerState<PosPaymentSheet> createState() => _PosPaymentSheetState();
}

class _PosPaymentSheetState extends ConsumerState<PosPaymentSheet> {
  bool _isProcessing = false;
  String _paymentMethod = 'cash'; // 'cash' | 'transfer'

  Future<void> _processPayment() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final cart = ref.read(posCartProvider);
      final orderItems = cart.items
          .where((i) => !i.isGift)
          .map((i) => {
            'productId': i.product.id,
            'productName': i.product.name,
            'quantity': i.quantity,
            'unitPrice': i.product.basePrice,
          })
          .toList();

      // Add gift items as well
      final giftItems = cart.items
          .where((i) => i.isGift)
          .map((i) => {
            'productName': i.product.name,
            'quantity': i.quantity,
            'unitPrice': 0.0,
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
        paymentMethod: _paymentMethod,
      );

      // Clear cart
      ref.read(posCartProvider.notifier).clearCart();

      if (!mounted) return;

      // Show success
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(VN.thanhToanThanhCong)),
      );

      Navigator.pop(context); // close payment sheet

      // If cash, ask about printing receipt
      if (_paymentMethod == 'cash') {
        _askPrintReceipt(order.orderRef);
      } else {
        // Bank transfer: just close
        Navigator.pop(context); // close cart sheet
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _askPrintReceipt(String orderRef) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('In hóa đơn?'),
        content: const Text('Bạn có muốn in biên nhận không?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close cart sheet
            },
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close cart sheet
              // Navigate to receipt preview
              context.push('/orders/$orderRef/receipt?type=customer');
            },
            child: Text(VN.inBienNhan),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(posCartProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
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
                color: theme.colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Text(
                      VN.thanhToan,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Total amount
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Tổng cộng',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatVND(cart.total),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Payment method toggle
                    Text(
                      'Hình thức thanh toán',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'cash',
                          label: Text(VN.tienMat),
                          icon: const Icon(Icons.money),
                        ),
                        ButtonSegment(
                          value: 'transfer',
                          label: Text(VN.chuyenKhoan),
                          icon: const Icon(Icons.qr_code),
                        ),
                      ],
                      selected: {_paymentMethod},
                      onSelectionChanged: (set) {
                        setState(() => _paymentMethod = set.first);
                      },
                    ),
                    const Spacer(),

                    // Confirm button
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _processPayment,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        _isProcessing ? 'Đang xử lý...' : VN.xacNhanThanhToan,
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
}