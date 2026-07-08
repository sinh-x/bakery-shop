import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/order_draft.dart';
import '../../data/models/product.dart';
import '../../features/orders/widgets/order_wizard.dart';
import '../../shared/gift_config.dart';
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
  OrderCreateState build() =>
      const OrderCreateState(wizardData: OrderWizardData());

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
  void checkAutoGift() {
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

    final giftCatalog = _giftCatalogByNormalizedName();
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

  Map<String, Product> _giftCatalogByNormalizedName() {
    final products =
        ref.read(phuKienProductsProvider).asData?.value ?? const [];
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
    state = const OrderCreateState(wizardData: OrderWizardData());
  }
}

final orderCreateStateProvider =
    NotifierProvider<OrderCreateStateNotifier, OrderCreateState>(
  OrderCreateStateNotifier.new,
);
