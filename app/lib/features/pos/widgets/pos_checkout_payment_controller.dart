// DG-322 Phase 4: POS checkout payment + submission controller, extracted
// from pos_checkout_screen.dart to keep the screen under the 300-line
// threshold (NFR4). Owns the stage-5 payment state (method, amount, tien_rut,
// target account, transfer photo, skipPayment flag) and the pay-now /
// pay-later submit paths that drive the shared orchestrator's submitOrder.
import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/api/order_service.dart';
import '../../../data/api/payment_transaction_service.dart';
import '../../../data/models/order.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../providers/pos_provider.dart';
import '../../../data/providers/products_provider.dart';
import '../../../features/stock/stock_screen.dart';
import 'pos_checkout_dialogs.dart';
import 'package:bakery_app/shared/labels/orders.dart';
/// Callback the controller uses to invoke the shared orchestrator's
/// submission spine. Returns `true` when the order was created and
/// navigation fired.
typedef SubmitOrderFn = Future<bool> Function({
  String? status,
  String? paymentMethod,
});

/// Callback the controller uses to read the current POS wizard deliveryType
/// so it can resolve the createOrder `status` (pickup/delivery/door +
/// deliver-now).
typedef ResolveDeliveryTypeFn = String Function();

/// Callback the controller uses to transition the wizard to a new stage.
typedef GoToStageFn = void Function(int stage);

/// Callback the controller uses to write the wizard items back to the POS
/// cart (single source of truth at submit) before entering the payment step.
typedef WriteBackToCartFn = void Function();

/// Holds the POS stage-5 payment state and the pay-now / pay-later submit
/// paths. The screen delegates [PosPaymentStep] callbacks here so the
/// screen file stays a thin orchestrator wrapper (DG-322 Phase 4, NFR4).
class PosCheckoutPaymentController {
  PosCheckoutPaymentController({
    required this.submitOrder,
    required this.resolveDeliveryType,
    required this.goToStage,
    required this.writeBackToCart,
    this.backFromPaymentStepOverride,
  });

  final SubmitOrderFn submitOrder;
  final ResolveDeliveryTypeFn resolveDeliveryType;
  final GoToStageFn goToStage;
  final WriteBackToCartFn writeBackToCart;

  /// Optional override for the Stage 5 "Quay lại" action. When provided
  /// (e.g. by the Giao ngay fast-path, DG-370 Phase 1), this is called
  /// instead of the default [backFromPaymentStep] which returns to Stage 4.
  final VoidCallback? backFromPaymentStepOverride;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  String _selectedPaymentMethod = 'cash';
  String get selectedPaymentMethod => _selectedPaymentMethod;

  String? _selectedTargetAccount;
  String? get selectedTargetAccount => _selectedTargetAccount;

  double _paidAmount = 0;
  double get paidAmount => _paidAmount;

  double _cartTotal = 0;
  double get cartTotal => _cartTotal;

  bool _hasTienRut = false;
  bool get hasTienRut => _hasTienRut;

  double _tienRutAmount = 0;
  double get tienRutAmount => _tienRutAmount;

  // Transfer photo picked in the pay-now transfer path; handed to the
  // orchestrator's onUploadPendingPhotos hook.
  XFile? _pendingTransferPhoto;

  // Pay-later flag: when true, the onAfterSubmit / onUploadPendingPhotos
  // hooks skip payment-transaction creation and photo upload (matches the
  // pre-refactor `skipPayment` branch in `_createOrderInternal`).
  bool _skipPayment = false;
  bool get skipPayment => _skipPayment;

  // DG-370 Phase 3 — the fast-path "Giao ngay & Thanh toán" sets this so the
  // order is created with status "delivered" on BOTH pay-now and pay-later
  // (FR4). The normal 5-stage flow leaves this false (Stage 3 "Giao hàng sau"
  // / Stage 4 review path) and only pay-now flips it via the
  // `deliverImmediately` argument on [handlePayNow] / [enterPaymentStep].
  bool deliverImmediately = false;

  /// Enters the payment step from the Stage 4 review: writes the wizard items
  /// back to the cart, computes the cart total / tien_rut defaults, and
  /// advances to stage 5. Returns the new payment state so the caller can
  /// rebuild the [PosPaymentStep] with the fresh values.
  PosPaymentStepState enterPaymentStep(WidgetRef ref) {
    writeBackToCart();
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
    _cartTotal = cartTotal;
    _paidAmount = cartTotal;
    _hasTienRut = hasTienRut;
    _tienRutAmount = tienRutDefault;
    goToStage(5);
    return _snapshot();
  }

  PosPaymentStepState _snapshot() => PosPaymentStepState(
        orderTotal: _cartTotal,
        initialAmount: _paidAmount,
        hasTienRut: _hasTienRut,
        tienRutAmount: _tienRutAmount,
        selectedPaymentMethod: _selectedPaymentMethod,
        selectedTargetAccount: _selectedTargetAccount,
        isProcessing: _isProcessing,
      );

  void backFromPaymentStep() {
    if (backFromPaymentStepOverride != null) {
      backFromPaymentStepOverride!();
      return;
    }
    goToStage(4);
  }

  void onPaymentMethodChanged(String paymentMethod) {
    if (_selectedPaymentMethod == paymentMethod) return;
    _selectedPaymentMethod = paymentMethod;
    // Clear target account when leaving the transfer method (FR7 — the
    // selector is only meaningful for transfer).
    if (paymentMethod != 'transfer') {
      _selectedTargetAccount = null;
    }
  }

  void onAmountChanged(double amount) {
    _paidAmount = amount;
  }

  void onTienRutAmountChanged(double amount) {
    _tienRutAmount = amount;
  }

  void onTargetAccountChanged(String? account) {
    _selectedTargetAccount = account;
  }

  Future<void> _showExcessWarning(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(OrdersLabels.excessPaymentWarningTitle),
        content: const Text(OrdersLabels.excessPaymentWarningMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> handlePayNow(
    BuildContext context, {
    required bool deliverImmediately,
    bool mounted = true,
  }) async {
    if (_isProcessing) return;
    if (_paidAmount > _cartTotal) {
      await _showExcessWarning(context);
      return;
    }
    _isProcessing = true;
    try {
      if (_selectedPaymentMethod == 'transfer') {
        await _handleTransfer(
          context,
          deliverImmediately: deliverImmediately,
        );
      } else {
        await _submit(
          context,
          paymentMethod: 'cash',
          deliverImmediately: deliverImmediately,
          mounted: mounted,
        );
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> handlePayLater(BuildContext context, {bool mounted = true}) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _skipPayment = true;
    try {
      await _submit(
        context,
        paymentMethod: '',
        deliverImmediately: deliverImmediately,
        mounted: mounted,
      );
    } finally {
      _isProcessing = false;
      _skipPayment = false;
    }
  }

  Future<void> _handleTransfer(
    BuildContext context, {
    required bool deliverImmediately,
  }) async {
    final source = await showTransferSourceDialog(context);
    if (source == null || !context.mounted) return;

    if (source == 'skip') {
      await _submit(
        context,
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
    if (image == null || !context.mounted) return;

    _pendingTransferPhoto = image;
    await _submit(
      context,
      paymentMethod: 'transfer',
      deliverImmediately: deliverImmediately,
      showSuccessSnackbar: true,
    );
  }

  String _resolveStatus(bool deliverImmediately) {
    final deliveryType = resolveDeliveryType();
    final isDelivery = deliveryType == 'bus' || deliveryType == 'door';
    // B5: pickup defaults to 'confirmed'; "deliver now" → 'delivered'.
    return isDelivery
        ? 'new'
        : deliverImmediately
            ? 'delivered'
            : 'confirmed';
  }

  Future<void> _submit(
    BuildContext context, {
    required String paymentMethod,
    required bool deliverImmediately,
    bool showSuccessSnackbar = false,
    bool mounted = true,
  }) async {
    final status = _resolveStatus(deliverImmediately);
    final submitted = await submitOrder(
      status: status,
      paymentMethod: paymentMethod,
    );
    if (!submitted || !mounted || !context.mounted) {
      _pendingTransferPhoto = null;
      return;
    }
    // The orchestrator's onAfterSubmit hook runs createPaymentTransactions +
    // provider invalidation; onNavigateAfterSubmit fires pushReplacement.
    // _pendingTransferPhoto is consumed by the onUploadPendingPhotos hook.
    if (showSuccessSnackbar) {
      showTopSnackBar(context, OrdersLabels.thanhToanThanhCong);
    }
    _pendingTransferPhoto = null;
  }

  /// Uploads the transfer proof photo (tagged 'chuyen-khoan') and any per-item
  /// pending photos. Invoked by the orchestrator's onUploadPendingPhotos
  /// hook. Skips entirely when `skipPayment` (pay-later) is true — matches
  /// the pre-refactor `skipPayment` branch which omitted both photo upload
  /// and payment-transaction creation.
  Future<void> uploadOrderPhotos(
    WidgetRef ref,
    Order order,
    OrderCreateState state,
  ) async {
    if (_skipPayment) return;
    final orderService = ref.read(orderServiceProvider);

    if (_pendingTransferPhoto != null) {
      await orderService.uploadOrderPhoto(
        order.orderRef,
        _pendingTransferPhoto!,
        tags: 'chuyen-khoan',
      );
    }

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
  }

  /// Creates the payment transactions (full_payment / deposit + optional
  /// tien_rut) for the created order. Invoked by the orchestrator's
  /// onAfterSubmit hook. Skipped for the pay-later path (`skipPayment`).
  Future<void> createPaymentTransactions(
    Order order,
    String paymentMethod,
    WidgetRef ref,
  ) async {
    if (_skipPayment) return;
    final txnSvc = ref.read(paymentTransactionServiceProvider);
    final txnType = _paidAmount >= order.totalPrice
        ? 'full_payment'
        : 'deposit';
    await txnSvc.createTransaction(
      order.orderRef,
      amount: _paidAmount,
      type: txnType,
      method: paymentMethod,
      paymentSource: _selectedTargetAccount,
    );

    if (_hasTienRut && _tienRutAmount > 0) {
      await txnSvc.createTransaction(
        order.orderRef,
        amount: _tienRutAmount,
        type: 'tien_rut',
        method: paymentMethod,
        paymentSource: _selectedTargetAccount,
      );
    }
  }

  /// POS-specific post-submit cleanup: clear the POS cart and invalidate the
  /// product / stock providers so the POS grid refreshes after a sale.
  /// Invoked by the orchestrator's onAfterSubmit hook.
  void postSubmitCleanup(WidgetRef ref) {
    ref.read(posCartProvider.notifier).clearCart();
    ref.invalidate(productsProvider);
    ref.invalidate(stockOverviewProvider);
  }
}

/// Immutable snapshot of the payment-step state handed to [PosPaymentStep]
/// so the widget rebuilds with the fresh values when the screen re-renders.
class PosPaymentStepState {
  const PosPaymentStepState({
    required this.orderTotal,
    required this.initialAmount,
    required this.hasTienRut,
    required this.tienRutAmount,
    required this.selectedPaymentMethod,
    required this.selectedTargetAccount,
    required this.isProcessing,
  });

  final double orderTotal;
  final double initialAmount;
  final bool hasTienRut;
  final double tienRutAmount;
  final String selectedPaymentMethod;
  final String? selectedTargetAccount;
  final bool isProcessing;
}