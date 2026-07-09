import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/customer_service.dart';
import '../../data/models/order_draft.dart';
import '../../data/models/product.dart';
import '../../features/orders/widgets/order_wizard.dart';
import '../../shared/gift_config.dart';
import '../../shared/utils/order_helpers.dart';
import '../products_provider.dart';

class OrderCreateState {
  final List<DraftOrderItem> items;
  final OrderWizardData wizardData;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final String source;
  final int currentStage;
  final String? selectedCategorySlug;

  const OrderCreateState({
    this.items = const [],
    required this.wizardData,
    this.dueDate,
    this.dueTime,
    this.source = '',
    this.currentStage = 1,
    this.selectedCategorySlug,
  });

  bool canNavigateToStage(int stage) {
    if (stage <= currentStage) return true;
    if (stage >= 2 && items.isEmpty) return false;
    if (stage >= 3 && wizardData.customerName.isEmpty) return false;
    if (stage >= 4 && wizardData.needsAddress && wizardData.deliveryAddress.trim().isEmpty) {
      return false;
    }
    return true;
  }

  OrderCreateState copyWith({
    List<DraftOrderItem>? items,
    OrderWizardData? wizardData,
    DateTime? dueDate,
    TimeOfDay? dueTime,
    String? source,
    int? currentStage,
    String? selectedCategorySlug,
    bool clearSelectedCategorySlug = false,
  }) {
    return OrderCreateState(
      items: items ?? this.items,
      wizardData: wizardData ?? this.wizardData,
      dueDate: dueDate ?? this.dueDate,
      dueTime: dueTime ?? this.dueTime,
      source: source ?? this.source,
      currentStage: currentStage ?? this.currentStage,
      selectedCategorySlug: clearSelectedCategorySlug
          ? null
          : selectedCategorySlug ?? this.selectedCategorySlug,
    );
  }
}

class OrderCreateStateNotifier extends Notifier<OrderCreateState> {
  @override
  OrderCreateState build() {
    final defaultDue = defaultDueDateTime(DateTime.now());
    return OrderCreateState(
      wizardData: const OrderWizardData(),
      dueDate: DateTime(defaultDue.year, defaultDue.month, defaultDue.day),
      dueTime: TimeOfDay(hour: defaultDue.hour, minute: defaultDue.minute),
    );
  }

  void updateItems(List<DraftOrderItem> items) {
    state = state.copyWith(items: items);
  }

  void updateWizardData(OrderWizardData wizardData) {
    state = state.copyWith(wizardData: wizardData);
  }

  void updateDueDate(DateTime? dueDate) {
    state = state.copyWith(dueDate: dueDate);
  }

  void updateDueTime(TimeOfDay? dueTime) {
    state = state.copyWith(dueTime: dueTime);
  }

  void updateSource(String source) {
    state = state.copyWith(source: source);
  }

  void goToStage(int stage) {
    state = state.copyWith(currentStage: stage);
  }

  void updateSelectedCategorySlug(String? slug) {
    state = slug == null
        ? state.copyWith(clearSelectedCategorySlug: true)
        : state.copyWith(selectedCategorySlug: slug);
  }

  Future<void> restoreCustomerFromDraft(int customerId) async {
    try {
      final service = ref.read(customerServiceProvider);
      final customer = await service.getCustomer(customerId);
      final updated = state.wizardData.copyWith(
        selectedCustomer: customer,
        customerName: customer.name,
        customerPhone: customer.phone,
      );
      state = state.copyWith(wizardData: updated);
    } catch (e) {
      debugPrint('[OrderCreateState] restoreCustomerFromDraft failed: $e');
    }
  }

  /// Adds a catalog (phu_kien) extra to the items list. If an existing
  /// matching extra (same product, same gift flag, same unit price) is
  /// present, its quantity is incremented instead of adding a duplicate.
  void addCatalogExtra({
    required Product product,
    int? priceChipId,
    double? customUnitPrice,
    bool isGift = false,
  }) {
    final items = List<DraftOrderItem>.from(state.items);
    final normalizedUnitPrice = customUnitPrice ?? product.basePrice;
    final existing = items
        .where(
          (i) =>
              i.isExtra &&
              i.product.id == product.id &&
              i.isGift == isGift &&
              i.unitPrice == normalizedUnitPrice,
        )
        .firstOrNull;
    if (existing != null) {
      existing.quantity += 1;
    } else {
      items.add(
        createCatalogExtraItem(
          product: product,
          isGift: isGift,
          priceChipId: priceChipId,
          customUnitPrice: customUnitPrice,
        ),
      );
    }
    state = state.copyWith(items: items);
  }

  /// Auto-adds gift extras when tang_kem products total >= [GiftConfig.giftThreshold].
  ///
  /// Matches gift-configured extras (by normalized name) to active phu_kien
  /// catalog products and adds them as isGift=true items. Existing gifts are
  /// incremented instead of duplicated. This mirrors the legacy auto-gift
  /// behavior from the pre-refactor order_create_screen (commit bd17e17) and
  /// the POS cart (pos_provider.dart).
  ///
  /// Waits for [phuKienProductsProvider] to load so the gift catalog is
  /// available on the first product selection (FB-3).
  Future<void> checkAutoGift() async {
    final items = state.items;
    final hasTangKem = items.any(
      (i) =>
          !i.isExtra &&
          i.product.attributes['tang_kem']?.toString() == 'true',
    );
    if (!hasTangKem) return;

    final qualifiedTotal = items
        .where(
          (i) =>
              !i.isGift &&
              i.product.attributes['tang_kem']?.toString() == 'true',
        )
        .fold<double>(0, (sum, i) => sum + i.unitPrice * i.quantity);

    if (qualifiedTotal < GiftConfig.giftThreshold) return;

    final giftCatalog = await _giftCatalogByNormalizedName();
    if (giftCatalog.isEmpty) return;

    final updated = List<DraftOrderItem>.from(items);
    var changed = false;
    for (final (configuredName, configuredPrice) in GiftConfig.giftExtras) {
      final normalized = configuredName.trim().toLowerCase();
      final giftProduct = giftCatalog[normalized];
      if (giftProduct == null) continue;

      final existingGift = updated
          .where((i) => i.product.id == giftProduct.id && i.isGift)
          .firstOrNull;
      if (existingGift != null) {
        existingGift.quantity += 1;
        changed = true;
        continue;
      }

      updated.add(
        createCatalogExtraItem(
          product: giftProduct,
          isGift: true,
          customUnitPrice: configuredPrice,
        ),
      );
      changed = true;
    }

    if (changed) {
      state = state.copyWith(items: updated);
    }
  }

  Future<Map<String, Product>> _giftCatalogByNormalizedName() async {
    final asyncValue = ref.read(phuKienProductsProvider);
    final products = asyncValue.maybeWhen(
      data: (products) => products,
      orElse: () => <Product>[],
    );
    if (products.isEmpty) {
      final future = ref.read(phuKienProductsProvider.future);
      try {
        final loaded = await future;
        return _buildGiftCatalogMap(loaded);
      } catch (e) {
        debugPrint('[OrderCreateState] checkAutoGift gift catalog load failed: $e');
        return {};
      }
    }
    return _buildGiftCatalogMap(products);
  }

  Map<String, Product> _buildGiftCatalogMap(List<Product> products) {
    final byName = <String, Product>{};
    for (final product in products) {
      final normalized = product.name.trim().toLowerCase();
      if (normalized.isNotEmpty) {
        byName.putIfAbsent(normalized, () => product);
      }
    }
    return byName;
  }

  void reset() {
    final defaultDue = defaultDueDateTime(DateTime.now());
    state = OrderCreateState(
      wizardData: const OrderWizardData(),
      dueDate: DateTime(defaultDue.year, defaultDue.month, defaultDue.day),
      dueTime: TimeOfDay(hour: defaultDue.hour, minute: defaultDue.minute),
    );
  }
}

final orderCreateStateProvider =
    NotifierProvider<OrderCreateStateNotifier, OrderCreateState>(
  OrderCreateStateNotifier.new,
);

final posOrderStateProvider =
    NotifierProvider<OrderCreateStateNotifier, OrderCreateState>(
  OrderCreateStateNotifier.new,
);
