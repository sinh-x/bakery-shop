// EXEMPT: 300-line screen threshold — orchestrates 4 wizard stages + 2 payment
// paths (cash/transfer+photo) + editable amount + photo upload + status
// confirmation. Reviewed 2026-07-09 DG-218.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/order_service.dart';
import '../../data/api/payment_transaction_service.dart';
import '../../features/orders/widgets/order_stage_indicator.dart';
import '../../features/orders/widgets/order_wizard.dart';
import '../../features/orders/widgets/stage1_product_selection_screen.dart';
import '../../features/orders/widgets/stage2_customer_info_screen.dart';
import '../../features/orders/widgets/stage3_delivery_options_screen.dart';
import '../../features/pos/widgets/pos_checkout_dialogs.dart';
import '../../features/pos/widgets/pos_payment_step.dart';
import '../../features/pos/widgets/pos_review_panel.dart';
import '../../features/stock/stock_screen.dart';
import '../../providers/order/order_create_state_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/labels/orders.dart';
import '../pos/utils/pos_cart_wizard_sync.dart';
import '../../shared/utils/order_helpers.dart';
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
  double _paidAmount = 0;
  double _cartTotal = 0;
  bool _hasTienRut = false;
  double _tienRutAmount = 0;

  bool _paymentStepActive = false;
  bool _posStateInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPosState();
    });
  }

  void _initPosState() {
    if (_posStateInitialized) return;
    _posStateInitialized = true;

    final posNotifier = ref.read(posOrderStateProvider.notifier);
    final cart = ref.read(posCartProvider);

    // B1: seed items from cart losslessly via cartItemToDraft (DG-223 FR-2)
    final items = cart.items.map(cartItemToDraft).toList();
    posNotifier.updateItems(items);

    const wizardData = OrderWizardData(
      customerName: VN.khachLe,
      source: VN.taiTiemPOS,
      deliveryType: 'pickup',
    );
    posNotifier.updateWizardData(wizardData);
    posNotifier.updateSource(VN.taiTiemPOS);
    final posDue = posDefaultDueDateTime(DateTime.now());
    posNotifier.updateDueDate(DateTime(posDue.year, posDue.month, posDue.day));
    posNotifier.updateDueTime(TimeOfDay(hour: posDue.hour, minute: posDue.minute));
    posNotifier.goToStage(1);
  }

  void _goToStage(int stage) {
    ref.read(posOrderStateProvider.notifier).goToStage(stage);
    if (stage == 4) {
      setState(() => _paymentStepActive = false);
    }
  }

  void _writeBackToCart() {
    final state = ref.read(posOrderStateProvider);
    if (state.items.isEmpty) return;
    final cartItems = state.items.map(draftItemToCart).toList();
    ref.read(posCartProvider.notifier).replaceCart(cartItems);
  }

  void _onStage1Continue() {
    _goToStage(2);
  }

  void _onStage2Continue() {
    final state = ref.read(posOrderStateProvider);
    if (state.wizardData.deliveryType == 'pickup') {
      _goToStage(4);
    } else {
      _goToStage(3);
    }
  }

  void _enterPaymentStep() {
    final cart = ref.read(posCartProvider);
    final cartTotal = cart.items
        .where((i) => !i.isGift)
        .fold<double>(0, (sum, i) => sum + i.total);
    final tienRutItems = cart.items.where((i) => i.rutTien).toList();
    final hasTienRut = tienRutItems.isNotEmpty;
    final tienRutDefault = tienRutItems.fold<double>(
      0,
      (sum, i) => sum + (i.cashAmount ?? 0),
    );
    setState(() {
      _paymentStepActive = true;
      _cartTotal = cartTotal;
      _paidAmount = cartTotal;
      _hasTienRut = hasTienRut;
      _tienRutAmount = tienRutDefault;
    });
  }

  void _backFromPaymentStep() {
    setState(() => _paymentStepActive = false);
  }

  void _onPaymentMethodChanged(String paymentMethod) {
    if (_selectedPaymentMethod == paymentMethod) return;
    setState(() => _selectedPaymentMethod = paymentMethod);
  }

  void _onAmountChanged(double amount) {
    setState(() => _paidAmount = amount);
  }

  void _onTienRutAmountChanged(double amount) {
    setState(() => _tienRutAmount = amount);
  }

  Future<void> _showExcessWarning() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.excessPaymentWarningTitle),
        content: const Text(VN.excessPaymentWarningMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildOrderItems() {
    final state = ref.read(posOrderStateProvider);
    return state.items.map((i) {
      // Map<String, dynamic> matches the API layer convention
      // (OrderService.createOrder accepts List<Map<String, dynamic>>).
      final m = <String, dynamic>{
        'productId': i.product.id.toString(),
        'productName': i.product.name,
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'isExtra': i.isExtra,
        'isGift': i.isGift,
        'isBirthday': i.isBirthday,
        'attributes': i.attributes,
        'priceChipId': i.priceChipId,
      };
      if (i.isBirthday && i.age.isNotEmpty) {
        final age = int.tryParse(i.age.trim());
        if (age != null) m['age'] = age;
      }
      return m;
    }).toList();
  }

  Future<void> _handleFinalizeOrder() async {
    if (_isProcessing) return;
    if (_paidAmount > _cartTotal) {
      await _showExcessWarning();
      return;
    }
    setState(() => _isProcessing = true);
    try {
      // B5: pickup → "Giao ngay?" confirmation dialog
      final state = ref.read(posOrderStateProvider);
      final isDelivery = state.wizardData.deliveryType == 'bus' ||
          state.wizardData.deliveryType == 'door';
      bool deliverImmediately = false;
      if (!isDelivery) {
        deliverImmediately = await _confirmDeliverNow() ?? false;
        if (!mounted) return;
      }

      if (_selectedPaymentMethod == 'transfer') {
        await _handleTransfer(deliverImmediately: deliverImmediately);
      } else {
        await _createOrder('cash', deliverImmediately: deliverImmediately);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool?> _confirmDeliverNow() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.deliverNow),
        content: const Text(VN.deliverNowPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(VN.deliverNowNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(VN.deliverNowYes),
          ),
        ],
      ),
    );
  }

  Future<void> _createOrder(
    String paymentMethod, {
    bool deliverImmediately = false,
  }) async {
    await _createOrderInternal(
      paymentMethod: paymentMethod,
      deliverImmediately: deliverImmediately,
    );
  }

  Future<void> _handleTransfer({
    bool deliverImmediately = false,
  }) async {
    final source = await showTransferSourceDialog(context);
    if (source == null) return;

    if (source == 'skip') {
      await _createOrderInternal(
        paymentMethod: 'transfer',
        deliverImmediately: deliverImmediately,
      );
      return;
    }

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source as ImageSource,
      imageQuality: 85,
    );
    if (image == null) return;

    await _createOrderInternal(
      paymentMethod: 'transfer',
      deliverImmediately: deliverImmediately,
      transferPhoto: image,
      showSuccessSnackbar: true,
    );
  }

  Future<void> _createOrderInternal({
    required String paymentMethod,
    required bool deliverImmediately,
    XFile? transferPhoto,
    bool showSuccessSnackbar = false,
  }) async {
    setState(() => _isProcessing = true);

    try {
      final state = ref.read(posOrderStateProvider);
      final data = state.wizardData;
      final orderItems = _buildOrderItems();
      final dueDate = state.dueDate != null
          ? formatApiDate(state.dueDate!)
          : posCheckoutLocalDueDate(DateTime.now());
      final dueTime = state.dueTime != null
          ? formatHourMinute(state.dueTime!.hour, state.dueTime!.minute)
          : null;
      final isDelivery = data.deliveryType == 'bus' ||
          data.deliveryType == 'door';
      // B5: pickup defaults to 'confirmed'; "deliver now" → 'delivered'
      final status = isDelivery
          ? 'new'
          : deliverImmediately
              ? 'delivered'
              : 'confirmed';

      final orderService = ref.read(orderServiceProvider);
      final order = await orderService.createOrder(
        customerName: data.customerName.isNotEmpty
            ? data.customerName
            : VN.khachLe,
        customerPhone: data.customerPhone,
        customerId: data.selectedCustomer?.id,
        source: VN.taiTiemPOS,
        dueDate: dueDate,
        dueTime: dueTime,
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

      if (transferPhoto != null) {
        await orderService.uploadOrderPhoto(
          order.orderRef,
          transferPhoto,
          tags: 'chuyen-khoan',
        );
      }

      // B2: upload per-item cake photos
      final hasPerItemPhotos =
          state.items.any((i) => i.pendingPhotos.isNotEmpty);
      if (hasPerItemPhotos) {
        for (final draftItem in state.items) {
          if (draftItem.pendingPhotos.isEmpty) continue;
          for (final xfile in draftItem.pendingPhotos) {
            try {
              await orderService.uploadOrderPhoto(
                order.orderRef,
                xfile,
              );
            } catch (e) {
              if (kDebugMode) {
                debugPrint('Photo upload failed (${xfile.path}): $e');
              }
            }
          }
        }
      }

      // B3: always create a payment transaction
      final txnSvc = ref.read(paymentTransactionServiceProvider);
      final txnType = _paidAmount >= order.totalPrice
          ? 'full_payment'
          : 'deposit';
      await txnSvc.createTransaction(
        order.orderRef,
        amount: _paidAmount,
        type: txnType,
        method: paymentMethod,
      );

      if (_hasTienRut && _tienRutAmount > 0) {
        await txnSvc.createTransaction(
          order.orderRef,
          amount: _tienRutAmount,
          type: 'tien_rut',
          method: paymentMethod,
        );
      }

      if (!mounted) return;
      _navigatingAfterCheckout = true;
      if (showSuccessSnackbar) {
        showTopSnackBar(context, VN.thanhToanThanhCong);
      }
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

    final state = ref.watch(posOrderStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.thanhToan),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: VN.backToCart,
          onPressed: () {
            _writeBackToCart();
            context.pop();
          },
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
            child: OrderStageIndicator(
              currentStage: state.currentStage,
              onStageTap: (s) {
                if (state.canNavigateToStage(s)) _goToStage(s);
              },
            ),
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
        1 => Stage1ProductSelectionScreen(
            key: const ValueKey('stage1'),
            onContinue: _onStage1Continue,
            orderStateProvider: posOrderStateProvider,
          ),
        2 => Stage2CustomerInfoScreen(
            key: const ValueKey('stage2'),
            posMode: true,
            onBack: () {
              _writeBackToCart();
              context.pop();
            },
            onContinue: _onStage2Continue,
            orderStateProvider: posOrderStateProvider,
          ),
        3 => Stage3DeliveryOptionsScreen(
            key: const ValueKey('stage3'),
            onBack: () => _goToStage(2),
            onContinue: () => _goToStage(4),
            orderStateProvider: posOrderStateProvider,
          ),
        4 => _paymentStepActive
            ? PosPaymentStep(
                key: const ValueKey('pos-payment'),
                orderTotal: _cartTotal,
                initialAmount: _paidAmount,
                hasTienRut: _hasTienRut,
                tienRutAmount: _tienRutAmount,
                selectedPaymentMethod: _selectedPaymentMethod,
                isProcessing: _isProcessing,
                onPaymentMethodChanged: _onPaymentMethodChanged,
                onAmountChanged: _onAmountChanged,
                onTienRutAmountChanged: _onTienRutAmountChanged,
                onBack: _backFromPaymentStep,
                onSubmit: _handleFinalizeOrder,
              )
            : PosReviewPanel(
                key: const ValueKey('stage4'),
                onBack: () {
                  final data =
                      ref.read(posOrderStateProvider).wizardData;
                  _goToStage(
                      data.deliveryType == 'pickup' ? 2 : 3);
                },
                onContinue: _enterPaymentStep,
                orderStateProvider: posOrderStateProvider,
              ),
        _ => const SizedBox.shrink(),
      },
    );
  }

}
