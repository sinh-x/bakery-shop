import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/order_service.dart';
import '../../features/orders/widgets/order_stage_indicator.dart';
import '../../features/orders/widgets/order_wizard.dart';
import '../../features/orders/widgets/stage1_product_selection_screen.dart';
import '../../features/orders/widgets/stage2_customer_info_screen.dart';
import '../../features/orders/widgets/stage3_delivery_options_screen.dart';
import '../../features/pos/utils/pos_cart_item_display.dart';
import '../../features/pos/utils/pos_cart_wizard_sync.dart';
import '../../features/pos/widgets/pos_checkout_dialogs.dart';
import '../../features/pos/widgets/pos_payment_step.dart';
import '../../features/pos/widgets/pos_review_panel.dart';
import '../../features/stock/stock_screen.dart';
import '../../providers/order/order_create_state_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/labels/orders.dart';
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
  // Stage 4 sub-step: review → payment (DG-218 Phase 4, FR-5). When true the
  // dedicated payment step is shown after the review; when false the
  // review-only panel is shown.
  bool _paymentStepActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPosState();
    });
  }

  void _initPosState() {
    final notifier = ref.read(orderCreateStateProvider.notifier);
    // POS defaults: delivery type = pickup, due time = now ceil-rounded to the
    // next 15-minute slot (no +1h offset). See FR-3 / FR-4.
    const wizardData = OrderWizardData(
      customerName: VN.khachLe,
      source: VN.taiTiemPOS,
      deliveryType: 'pickup',
    );
    notifier.updateWizardData(wizardData);
    notifier.updateSource(VN.taiTiemPOS);
    final posDue = posDefaultDueDateTime(DateTime.now());
    notifier.updateDueDate(DateTime(posDue.year, posDue.month, posDue.day));
    notifier.updateDueTime(TimeOfDay(hour: posDue.hour, minute: posDue.minute));
    notifier.goToStage(2);
  }

  void _goToStage(int stage) {
    // Stage 1 (product selection) edits the wizard working copy
    // (`orderCreateStateProvider.items`); the POS cart is the single source
    // of truth at submit (DG-218 FR-2). When leaving Stage 1, write the
    // wizard edits back to the cart; when entering Stage 1, seed the wizard
    // working copy from the cart.
    final currentStage = ref.read(orderCreateStateProvider).currentStage;
    if (currentStage == 1 && stage != 1) {
      syncWizardItemsToCart(ref);
    }
    if (stage == 1 && currentStage != 1) {
      syncCartToWizardItems(ref);
    }
    // Entering Stage 4: sync the cart into the wizard working copy so the
    // unified summary cards (ProductSummaryCard etc.) reflect the latest
    // cart contents. Reset to the review sub-step (DG-218 Phase 4, FR-5).
    if (stage == 4) {
      syncCartToWizardItems(ref);
      setState(() => _paymentStepActive = false);
    }
    ref.read(orderCreateStateProvider.notifier).goToStage(stage);
  }

  void _onStage1Continue() {
    // Stage 1 → Stage 2: persist wizard edits back to the POS cart (single
    // source of truth at submit) before advancing.
    syncWizardItemsToCart(ref);
    _goToStage(2);
  }

  void _onStage2Continue() {
    final state = ref.read(orderCreateStateProvider);
    if (state.wizardData.deliveryType == 'pickup') {
      _goToStage(4);
    } else {
      _goToStage(3);
    }
  }

  void _enterPaymentStep() {
    // Review → dedicated payment step (DG-218 Phase 4, FR-5).
    setState(() => _paymentStepActive = true);
  }

  void _backFromPaymentStep() {
    // Payment → review sub-step.
    setState(() => _paymentStepActive = false);
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
      final dueDate = state.dueDate != null
          ? formatApiDate(state.dueDate!)
          : posCheckoutLocalDueDate(DateTime.now());
      final dueTime = state.dueTime != null
          ? formatHourMinute(state.dueTime!.hour, state.dueTime!.minute)
          : null;
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
      final dueDate = state.dueDate != null
          ? formatApiDate(state.dueDate!)
          : posCheckoutLocalDueDate(DateTime.now());
      final dueTime = state.dueTime != null
          ? formatHourMinute(state.dueTime!.hour, state.dueTime!.minute)
          : null;
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
        dueTime: dueTime,
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
          ),
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
        4 => _paymentStepActive
            ? PosPaymentStep(
                key: const ValueKey('pos-payment'),
                selectedPaymentMethod: _selectedPaymentMethod,
                isProcessing: _isProcessing,
                onPaymentMethodChanged: _onPaymentMethodChanged,
                onBack: _backFromPaymentStep,
                onSubmit: _handleFinalizeOrder,
              )
            : PosReviewPanel(
                key: const ValueKey('stage4'),
                onBack: () {
                  final data = ref.read(orderCreateStateProvider).wizardData;
                  _goToStage(data.deliveryType == 'pickup' ? 2 : 3);
                },
                onContinue: _enterPaymentStep,
              ),
        _ => const SizedBox.shrink(),
      },
    );
  }

}
