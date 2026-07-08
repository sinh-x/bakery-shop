import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../features/orders/utils/trung_bay_inventory_extensions.dart';
import 'enum_attribute.dart';
import 'product.dart';

class DraftOrderItem {
  final Product product;
  int quantity;
  String notes;
  bool isBirthday;
  String age;
  List<XFile> pendingPhotos;
  double? customUnitPrice;
  bool isExtra;
  bool isGift;
  Map<String, dynamic> attributes;
  bool daDuaTienRut;
  int? priceChipId;

  DraftOrderItem({
    required this.product,
    this.quantity = 1,
    this.notes = '',
    this.isBirthday = false,
    this.age = '',
    List<XFile>? pendingPhotos,
    this.customUnitPrice,
    this.isExtra = false,
    this.isGift = false,
    Map<String, dynamic>? attributes,
    this.daDuaTienRut = false,
    this.priceChipId,
  }) : pendingPhotos = pendingPhotos ?? [],
       attributes = _populateEnumDefaults(product, attributes);

  static Map<String, dynamic> _populateEnumDefaults(
    Product product,
    Map<String, dynamic>? provided,
  ) {
    final attrs = <String, dynamic>{...?provided};
    if (product.isTrungBay && !attrs.containsKey('useInventory')) {
      attrs['useInventory'] = 'false';
    }
    for (final ea in product.enumAttributes) {
      if (ea.options.isEmpty) continue;
      if (attrs.containsKey(ea.attributeType)) continue;
      EnumOption? defaultOpt;
      for (final o in ea.options) {
        if (o.isDefault) {
          defaultOpt = o;
          break;
        }
      }
      if (defaultOpt == null && ea.defaultOptionId != null) {
        for (final o in ea.options) {
          if (o.id == ea.defaultOptionId) {
            defaultOpt = o;
            break;
          }
        }
      }
      if (defaultOpt == null) {
        for (final o in ea.options) {
          if (o.active == 1) {
            defaultOpt = o;
            break;
          }
        }
      }
      defaultOpt ??= ea.options.first;
      attrs[ea.attributeType] = defaultOpt.valueVi;
    }
    return attrs;
  }

  double get unitPrice => customUnitPrice ?? product.basePrice;
}

DraftOrderItem createExtraItem(
  String extraName,
  double extraPrice, {
  bool isGift = false,
}) {
  final fakeProduct = Product(
    id: 0,
    name: extraName,
    category: 'extra',
    basePrice: extraPrice,
  );
  return DraftOrderItem(
    product: fakeProduct,
    quantity: 1,
    isExtra: true,
    isGift: isGift,
    customUnitPrice: extraPrice,
  );
}

DraftOrderItem createCatalogExtraItem({
  required Product product,
  int quantity = 1,
  bool isGift = false,
  int? priceChipId,
  double? customUnitPrice,
}) {
  final selectedChipId = customUnitPrice == null ? priceChipId : null;
  double? chipPrice;
  if (selectedChipId != null) {
    for (final chip in product.priceChips) {
      if (chip.id == selectedChipId) {
        chipPrice = chip.price;
        break;
      }
    }
  }

  return DraftOrderItem(
    product: product,
    quantity: quantity,
    isExtra: true,
    isGift: isGift,
    customUnitPrice: customUnitPrice ?? chipPrice,
    priceChipId: selectedChipId,
  );
}

class DraftPendingPhoto {
  final XFile file;
  Set<String> tags;
  DraftPendingPhoto({required this.file, Set<String>? tags}) : tags = tags ?? {};
}

class OrderDraft {
  final String customerName;
  final String customerPhone;
  final String deliveryPhone;
  final List<DraftOrderItem> items;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final String deliveryType;
  final String deliveryAddress;
  final String notes;
  final bool depositEnabled;
  final String depositAmount;
  final String depositMethod;
  final List<DraftPendingPhoto> pendingPhotos;
  final String source;
  final int currentStage;
  final String? selectedCategorySlug;

  OrderDraft({
    this.customerName = '',
    this.customerPhone = '',
    this.deliveryPhone = '',
    List<DraftOrderItem>? items,
    this.dueDate,
    this.dueTime,
    this.deliveryType = 'pickup',
    this.deliveryAddress = '',
    this.notes = '',
    this.depositEnabled = false,
    this.depositAmount = '',
    this.depositMethod = 'cash',
    List<DraftPendingPhoto>? pendingPhotos,
    this.source = '',
    this.currentStage = 1,
    this.selectedCategorySlug,
  }) : items = items ?? [],
       pendingPhotos = pendingPhotos ?? [];

  bool get isNotEmpty =>
      customerName.isNotEmpty ||
      customerPhone.isNotEmpty ||
      deliveryPhone.isNotEmpty ||
      items.isNotEmpty ||
      dueDate != null ||
      dueTime != null ||
      deliveryType != 'pickup' ||
      deliveryAddress.isNotEmpty ||
      notes.isNotEmpty ||
      depositEnabled ||
      depositAmount.isNotEmpty ||
      pendingPhotos.isNotEmpty ||
      source.isNotEmpty ||
      currentStage != 1 ||
      selectedCategorySlug != null;
}
