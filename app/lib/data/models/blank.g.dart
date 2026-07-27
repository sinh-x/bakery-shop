// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'blank.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Blank _$BlankFromJson(Map<String, dynamic> json) => _Blank(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  category: json['category'] as String? ?? '',
  unit: json['unit'] as String? ?? '',
  notes: json['notes'] as String? ?? '',
  createdAt: json['createdAt'] as String?,
  updatedAt: json['updatedAt'] as String?,
);

Map<String, dynamic> _$BlankToJson(_Blank instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'category': instance.category,
  'unit': instance.unit,
  'notes': instance.notes,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
};

_BlankCreate _$BlankCreateFromJson(Map<String, dynamic> json) => _BlankCreate(
  name: json['name'] as String,
  category: json['category'] as String? ?? '',
  unit: json['unit'] as String? ?? '',
  notes: json['notes'] as String? ?? '',
);

Map<String, dynamic> _$BlankCreateToJson(_BlankCreate instance) =>
    <String, dynamic>{
      'name': instance.name,
      'category': instance.category,
      'unit': instance.unit,
      'notes': instance.notes,
    };

_BlankUpdate _$BlankUpdateFromJson(Map<String, dynamic> json) => _BlankUpdate(
  name: json['name'] as String?,
  category: json['category'] as String?,
  unit: json['unit'] as String?,
  notes: json['notes'] as String?,
);

Map<String, dynamic> _$BlankUpdateToJson(_BlankUpdate instance) =>
    <String, dynamic>{
      'name': instance.name,
      'category': instance.category,
      'unit': instance.unit,
      'notes': instance.notes,
    };

_ProductBlankBom _$ProductBlankBomFromJson(Map<String, dynamic> json) =>
    _ProductBlankBom(
      id: (json['id'] as num).toInt(),
      productId: (json['productId'] as num?)?.toInt(),
      priceChipId: (json['priceChipId'] as num?)?.toInt(),
      blankId: (json['blankId'] as num).toInt(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      createdAt: json['createdAt'] as String?,
    );

Map<String, dynamic> _$ProductBlankBomToJson(_ProductBlankBom instance) =>
    <String, dynamic>{
      'id': instance.id,
      'productId': instance.productId,
      'priceChipId': instance.priceChipId,
      'blankId': instance.blankId,
      'quantity': instance.quantity,
      'createdAt': instance.createdAt,
    };

_BomCreate _$BomCreateFromJson(Map<String, dynamic> json) => _BomCreate(
  blankId: (json['blankId'] as num).toInt(),
  quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
);

Map<String, dynamic> _$BomCreateToJson(_BomCreate instance) =>
    <String, dynamic>{
      'blankId': instance.blankId,
      'quantity': instance.quantity,
    };

_BomUpdate _$BomUpdateFromJson(Map<String, dynamic> json) =>
    _BomUpdate(quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0);

Map<String, dynamic> _$BomUpdateToJson(_BomUpdate instance) =>
    <String, dynamic>{'quantity': instance.quantity};

_BlankStockEntry _$BlankStockEntryFromJson(Map<String, dynamic> json) =>
    _BlankStockEntry(
      id: (json['id'] as num).toInt(),
      blankId: (json['blankId'] as num).toInt(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      producedDate: json['producedDate'] as String? ?? '',
      expiryDate: json['expiryDate'] as String?,
      type: json['type'] as String? ?? 'production',
      createdAt: json['createdAt'] as String?,
    );

Map<String, dynamic> _$BlankStockEntryToJson(_BlankStockEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'blankId': instance.blankId,
      'quantity': instance.quantity,
      'producedDate': instance.producedDate,
      'expiryDate': instance.expiryDate,
      'type': instance.type,
      'createdAt': instance.createdAt,
    };

_BlankStockSummary _$BlankStockSummaryFromJson(Map<String, dynamic> json) =>
    _BlankStockSummary(
      blankId: (json['blankId'] as num).toInt(),
      name: json['name'] as String,
      category: json['category'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      stock: (json['stock'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$BlankStockSummaryToJson(_BlankStockSummary instance) =>
    <String, dynamic>{
      'blankId': instance.blankId,
      'name': instance.name,
      'category': instance.category,
      'unit': instance.unit,
      'stock': instance.stock,
    };

_StockCreate _$StockCreateFromJson(Map<String, dynamic> json) => _StockCreate(
  blankId: (json['blankId'] as num).toInt(),
  quantity: (json['quantity'] as num).toDouble(),
  type: json['type'] as String,
  producedDate: json['producedDate'] as String? ?? '',
  expiryDate: json['expiryDate'] as String?,
);

Map<String, dynamic> _$StockCreateToJson(_StockCreate instance) =>
    <String, dynamic>{
      'blankId': instance.blankId,
      'quantity': instance.quantity,
      'type': instance.type,
      'producedDate': instance.producedDate,
      'expiryDate': instance.expiryDate,
    };

_BlankDemand _$BlankDemandFromJson(Map<String, dynamic> json) => _BlankDemand(
  blankId: (json['blankId'] as num).toInt(),
  name: json['name'] as String,
  category: json['category'] as String? ?? '',
  unit: json['unit'] as String? ?? '',
  demand: (json['demand'] as num?)?.toDouble() ?? 0.0,
  stock: (json['stock'] as num?)?.toDouble() ?? 0.0,
  shortage: (json['shortage'] as num?)?.toDouble() ?? 0.0,
);

Map<String, dynamic> _$BlankDemandToJson(_BlankDemand instance) =>
    <String, dynamic>{
      'blankId': instance.blankId,
      'name': instance.name,
      'category': instance.category,
      'unit': instance.unit,
      'demand': instance.demand,
      'stock': instance.stock,
      'shortage': instance.shortage,
    };

_BlankStockLog _$BlankStockLogFromJson(Map<String, dynamic> json) =>
    _BlankStockLog(
      id: (json['id'] as num).toInt(),
      blankId: (json['blankId'] as num).toInt(),
      quantityChange: (json['quantityChange'] as num).toDouble(),
      type: json['type'] as String,
      producedDate: json['producedDate'] as String?,
      expiryDate: json['expiryDate'] as String?,
      createdAt: json['createdAt'] as String?,
    );

Map<String, dynamic> _$BlankStockLogToJson(_BlankStockLog instance) =>
    <String, dynamic>{
      'id': instance.id,
      'blankId': instance.blankId,
      'quantityChange': instance.quantityChange,
      'type': instance.type,
      'producedDate': instance.producedDate,
      'expiryDate': instance.expiryDate,
      'createdAt': instance.createdAt,
    };
