import 'package:freezed_annotation/freezed_annotation.dart';

import 'work_item.dart';

part 'blank.freezed.dart';
part 'blank.g.dart';

/// A phôi (semi-finished good) that must be prepared before assembly.
///
/// Category is free-form text used to group blanks (e.g. "cot", "kem",
/// "nhan"). All JSON keys use camelCase per the DG-290 backend convention.
@freezed
sealed class Blank with _$Blank {
  const factory Blank({
    required int id,
    required String name,
    @Default('') String category,
    @Default('') String unit,
    @Default('') String notes,
    @JsonKey(name: 'createdAt') String? createdAt,
    @JsonKey(name: 'updatedAt') String? updatedAt,
  }) = _Blank;

  factory Blank.fromJson(Map<String, dynamic> json) => _$BlankFromJson(json);
}

/// Request body for `POST /api/blanks`.
@freezed
sealed class BlankCreate with _$BlankCreate {
  const factory BlankCreate({
    required String name,
    @Default('') String category,
    @Default('') String unit,
    @Default('') String notes,
  }) = _BlankCreate;

  factory BlankCreate.fromJson(Map<String, dynamic> json) =>
      _$BlankCreateFromJson(json);
}

/// Request body for `PATCH /api/blanks/{id}`. All fields optional.
@freezed
sealed class BlankUpdate with _$BlankUpdate {
  const factory BlankUpdate({
    String? name,
    String? category,
    String? unit,
    String? notes,
  }) = _BlankUpdate;

  factory BlankUpdate.fromJson(Map<String, dynamic> json) =>
      _$BlankUpdateFromJson(json);
}

/// BOM mapping row: a price_chip (or product) → blank + quantity.
@freezed
sealed class ProductBlankBom with _$ProductBlankBom {
  const factory ProductBlankBom({
    required int id,
    @JsonKey(name: 'productId') int? productId,
    @JsonKey(name: 'priceChipId') int? priceChipId,
    @JsonKey(name: 'blankId') required int blankId,
    @Default(1.0) double quantity,
    @JsonKey(name: 'createdAt') String? createdAt,
  }) = _ProductBlankBom;

  factory ProductBlankBom.fromJson(Map<String, dynamic> json) =>
      _$ProductBlankBomFromJson(json);
}

/// Request body for `POST /api/price-chips/{chipId}/blanks`.
@freezed
sealed class BomCreate with _$BomCreate {
  const factory BomCreate({
    @JsonKey(name: 'blankId') required int blankId,
    @Default(1.0) double quantity,
  }) = _BomCreate;

  factory BomCreate.fromJson(Map<String, dynamic> json) =>
      _$BomCreateFromJson(json);
}

/// Request body for `PATCH /api/price-chips/{chipId}/blanks/{bomId}`.
@freezed
sealed class BomUpdate with _$BomUpdate {
  const factory BomUpdate({
    @Default(1.0) double quantity,
  }) = _BomUpdate;

  factory BomUpdate.fromJson(Map<String, dynamic> json) =>
      _$BomUpdateFromJson(json);
}

/// A production/usage lot row tracking blank inventory.
///
/// `type` is either `"production"` (adds stock) or `"usage"` (subtracts
/// stock). For production lots `producedDate` and `expiryDate` record the
/// production batch freshness.
@freezed
sealed class BlankStockEntry with _$BlankStockEntry {
  const factory BlankStockEntry({
    required int id,
    @JsonKey(name: 'blankId') required int blankId,
    @Default(0.0) double quantity,
    @JsonKey(name: 'producedDate') @Default('') String producedDate,
    @JsonKey(name: 'expiryDate') String? expiryDate,
    @Default('production') String type,
    @JsonKey(name: 'createdAt') String? createdAt,
  }) = _BlankStockEntry;

  factory BlankStockEntry.fromJson(Map<String, dynamic> json) =>
      _$BlankStockEntryFromJson(json);
}

/// Current net stock per blank (response of `GET /api/blanks/stock`).
@freezed
sealed class BlankStockSummary with _$BlankStockSummary {
  const factory BlankStockSummary({
    @JsonKey(name: 'blankId') required int blankId,
    required String name,
    @Default('') String category,
    @Default('') String unit,
    @Default(0.0) double stock,
  }) = _BlankStockSummary;

  factory BlankStockSummary.fromJson(Map<String, dynamic> json) =>
      _$BlankStockSummaryFromJson(json);
}

/// Request body for `POST /api/blanks/stock`.
@freezed
sealed class StockCreate with _$StockCreate {
  const factory StockCreate({
    @JsonKey(name: 'blankId') required int blankId,
    required double quantity,
    required String type,
    @JsonKey(name: 'producedDate') @Default('') String producedDate,
    @JsonKey(name: 'expiryDate') String? expiryDate,
  }) = _StockCreate;

  factory StockCreate.fromJson(Map<String, dynamic> json) =>
      _$StockCreateFromJson(json);
}

/// Demand vs stock vs shortage per blank (response of `GET /api/blanks/demand`).
@freezed
sealed class BlankDemand with _$BlankDemand {
  const factory BlankDemand({
    @JsonKey(name: 'blankId') required int blankId,
    required String name,
    @Default('') String category,
    @Default('') String unit,
    @Default(0.0) double demand,
    @Default(0.0) double stock,
    @Default(0.0) double shortage,
  }) = _BlankDemand;

  factory BlankDemand.fromJson(Map<String, dynamic> json) =>
      _$BlankDemandFromJson(json);
}

/// Audit-log entry for every blank stock change (FR5).
@freezed
sealed class BlankStockLog with _$BlankStockLog {
  const factory BlankStockLog({
    required int id,
    @JsonKey(name: 'blankId') required int blankId,
    @JsonKey(name: 'quantityChange') required double quantityChange,
    required String type,
    @JsonKey(name: 'producedDate') String? producedDate,
    @JsonKey(name: 'expiryDate') String? expiryDate,
    @JsonKey(name: 'createdAt') String? createdAt,
  }) = _BlankStockLog;

  factory BlankStockLog.fromJson(Map<String, dynamic> json) =>
      _$BlankStockLogFromJson(json);
}

/// A product linked to a blank via the BOM mapping (`product_blank_bom`).
///
/// Returned by `GET /api/blanks/{id}/products` inside [BlankProducts.bomProducts].
class BlankBomProduct {
  const BlankBomProduct({
    required this.bomId,
    this.productId,
    required this.productName,
    this.productCategory = '',
    this.priceChipId,
    this.quantity = 0.0,
  });

  final int bomId;
  final int? productId;
  final String productName;
  final String productCategory;
  final int? priceChipId;
  final double quantity;

  factory BlankBomProduct.fromJson(Map<String, dynamic> json) => BlankBomProduct(
        bomId: (json['bomId'] as num).toInt(),
        productId: json['productId'] == null
            ? null
            : (json['productId'] as num).toInt(),
        productName: (json['productName'] as String?) ?? '',
        productCategory: (json['productCategory'] as String?) ?? '',
        priceChipId: json['priceChipId'] == null
            ? null
            : (json['priceChipId'] as num).toInt(),
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Reverse-lookup response for a blank: products linked via BOM and work
/// items linked via the `blank_id` FK (FR3 / DG-293 Phase 4).
class BlankProducts {
  const BlankProducts({
    required this.blankId,
    required this.bomProducts,
    required this.workItems,
  });

  final int blankId;
  final List<BlankBomProduct> bomProducts;
  final List<WorkItem> workItems;

  factory BlankProducts.fromJson(Map<String, dynamic> json) => BlankProducts(
        blankId: (json['blankId'] as num).toInt(),
        bomProducts: ((json['bomProducts'] as List?) ?? const [])
            .map((e) => BlankBomProduct.fromJson(e as Map<String, dynamic>))
            .toList(),
        workItems: ((json['workItems'] as List?) ?? const [])
            .map((e) => WorkItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}