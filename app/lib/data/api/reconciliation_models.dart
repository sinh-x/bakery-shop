class ReconciliationPriceChip {
  ReconciliationPriceChip({
    required this.id,
    required this.label,
    required this.price,
    required this.position,
  });

  final int id;
  final String label;
  final double price;
  final int position;

  factory ReconciliationPriceChip.fromJson(Map<String, dynamic> json) {
    return ReconciliationPriceChip(
      id: json['id'] as int,
      label: json['label'] as String,
      price: (json['price'] as num).toDouble(),
      position: json['position'] as int,
    );
  }
}

class ReconciliationDraftOption {
  ReconciliationDraftOption({
    required this.productId,
    required this.normalizedPrice,
    required this.chipLabel,
    required this.sourceChipIds,
    required this.sourceChipLabels,
    required this.expectedQty,
    this.priceChipId,
    this.grossAvailableQty,
    this.keyDiscriminator,
  });

  final int productId;
  final int normalizedPrice;
  final int? priceChipId;
  final String chipLabel;
  final List<int> sourceChipIds;
  final List<String> sourceChipLabels;
  final int expectedQty;

  /// Discriminator appended to the option key (`productId:price#<discriminator>`)
  /// only when this option collides at the same normalized price with a
  /// base-price option (chip_id=null) of the same product. Null for the
  /// non-collision case so the option key stays backward-compatible
  /// (`productId:price`). Set by `mergeOptionsByNormalizedPrice` (DG-413).
  final String? keyDiscriminator;

  /// Gross available quantity (available items before subtracting
  /// negative_balance). Used by the surplus indicator so it matches the
  /// backend's gross surplus calculation (counted - available) instead of
  /// the net position (counted - expected), which would inflate the
  /// displayed surplus when a negative balance exists
  /// (DG-200 Phase 5.6-c1-fix, M-1). Null when the backend did not provide it
  /// (falls back to expectedQty).
  final int? grossAvailableQty;

  /// Default counted quantity for this option when no explicit counted value
  /// has been recorded. Negative expected quantities (net position from a
  /// negative_balance) fall back to 0 so counted_qty stays non-negative
  /// (DG-200 Phase 5.6-c3-fix, Mn-1).
  int get defaultCountedQty => expectedQty < 0 ? 0 : expectedQty;

  String get chipLabelMetadata {
    if (sourceChipLabels.isEmpty) {
      return chipLabel;
    }
    return sourceChipLabels.join(', ');
  }

  factory ReconciliationDraftOption.fromJson(Map<String, dynamic> json) {
    final fallbackNormalizedPrice =
        (json['price'] as num?)?.round() ??
        (json['base_price'] as num?)?.round() ??
        0;
    final chipLabels =
        (json['source_chip_labels'] as List<dynamic>? ?? <dynamic>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
    return ReconciliationDraftOption(
      productId: json['product_id'] as int,
      normalizedPrice:
          (json['normalized_price'] as num?)?.toInt() ??
          fallbackNormalizedPrice,
      priceChipId: (json['price_chip_id'] as num?)?.toInt(),
      chipLabel: (json['chip_label'] as String?) ?? 'Gia goc',
      sourceChipIds: (json['source_chip_ids'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => (item as num).toInt())
          .toList(),
      sourceChipLabels: chipLabels,
      expectedQty: (json['expected_qty'] as num).toInt(),
      grossAvailableQty: (json['gross_available_qty'] as num?)?.toInt(),
    );
  }
}

class ReconciliationDraftProduct {
  ReconciliationDraftProduct({
    required this.productId,
    required this.name,
    required this.category,
    required this.expectedQty,
    required this.basePrice,
    required this.priceChips,
    List<ReconciliationDraftOption> options =
        const <ReconciliationDraftOption>[],
  }) : options = options.isEmpty
           ? [
               ReconciliationDraftOption(
                 productId: productId,
                 normalizedPrice: basePrice.round(),
                 priceChipId: null,
                 chipLabel: 'Gia goc',
                 sourceChipIds: const <int>[],
                 sourceChipLabels: const <String>[],
                 expectedQty: expectedQty,
               ),
             ]
           : options;

  final int productId;
  final String name;
  final String category;
  final int expectedQty;
  final double basePrice;
  final List<ReconciliationPriceChip> priceChips;
  final List<ReconciliationDraftOption> options;

  factory ReconciliationDraftProduct.fromJson(Map<String, dynamic> json) {
    final chips = (json['price_chips'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) =>
              ReconciliationPriceChip.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    final rawOptions = (json['options'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) =>
              ReconciliationDraftOption.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    final options = mergeOptionsByNormalizedPrice(rawOptions);
    return ReconciliationDraftProduct(
      productId: json['product_id'] as int,
      name: json['name'] as String,
      category: json['category'] as String,
      expectedQty: json['expected_qty'] as int,
      basePrice: (json['base_price'] as num).toDouble(),
      priceChips: chips,
      options: options,
    );
  }
}

List<ReconciliationDraftOption> mergeOptionsByNormalizedPrice(
  List<ReconciliationDraftOption> options,
) {
  // Group options by normalized price, preserving input order.
  final groups = <int, List<ReconciliationDraftOption>>{};
  final order = <int>[];
  for (final option in options) {
    final group = groups.putIfAbsent(option.normalizedPrice, () {
      order.add(option.normalizedPrice);
      return <ReconciliationDraftOption>[];
    });
    group.add(option);
  }

  final result = <ReconciliationDraftOption>[];
  for (final price in order) {
    final group = groups[price]!;
    if (group.length == 1) {
      result.add(group.single);
      continue;
    }

    // Split the group into base-price options (chip_id=null, no source chips)
    // and chip options. A base-price option colliding with a chip option at
    // the same normalized price must NOT be merged: the backend compares
    // expected_qty per price_chip_id, so collapsing base + chip into one line
    // produces a single expected_qty that cannot match both backend keys
    // (DG-413).
    final baseOptions = <ReconciliationDraftOption>[];
    final chipOptions = <ReconciliationDraftOption>[];
    for (final option in group) {
      if (_isBasePriceOption(option)) {
        baseOptions.add(option);
      } else {
        chipOptions.add(option);
      }
    }

    if (baseOptions.isEmpty) {
      // No base option at this price: merge chip options as before (existing
      // behavior for distinct chips at the same price).
      result.add(_mergeGroup(chipOptions));
      continue;
    }
    if (chipOptions.isEmpty) {
      // Multiple base options at the same price (defensive): merge as before.
      result.add(_mergeGroup(baseOptions));
      continue;
    }

    // Collision case: base + chip at the same price. Keep them separate with
    // discriminators so option keys distinguish them. When the chip group
    // contains more than one distinct chip id, split per chip so each
    // submit line carries its own price_chip_id — collapsing them would
    // null out priceChipId and collide with the base bucket (DG-413 CQ-1).
    const baseDiscriminator = 'base';
    result.add(_withDiscriminator(_mergeGroup(baseOptions), baseDiscriminator));
    for (final chipOption in _splitChipOptionsByChipId(chipOptions)) {
      result.add(chipOption);
    }
  }
  return result;
}

bool _isBasePriceOption(ReconciliationDraftOption option) {
  return option.priceChipId == null && option.sourceChipIds.isEmpty;
}

/// Splits chip options colliding with a base-price option into one merged
/// option per distinct chip id. Each emitted option preserves its
/// `priceChipId` and gets a `c<chipId>` discriminator so the submit line
/// targets the backend's `(product_id, chip_id)` bucket instead of falling
/// back to the base bucket (DG-413 CQ-1).
///
/// When all chip options resolve to a single chip id, this is equivalent to
/// the previous single-group behavior.
List<ReconciliationDraftOption> _splitChipOptionsByChipId(
  List<ReconciliationDraftOption> chipOptions,
) {
  // Group by the resolved chip id. Options whose chip id cannot be resolved
  // land in a single 'unknown' bucket merged together (defensive — the
  // backend payload always sets price_chip_id for chip options).
  final byChipId = <int, List<ReconciliationDraftOption>>{};
  final order = <int>[];
  final unknown = <ReconciliationDraftOption>[];
  for (final option in chipOptions) {
    final chipId = _singleChipId(option);
    if (chipId == null) {
      unknown.add(option);
      continue;
    }
    byChipId.putIfAbsent(chipId, () {
      order.add(chipId);
      return <ReconciliationDraftOption>[];
    }).add(option);
  }

  final result = <ReconciliationDraftOption>[];
  for (final chipId in order) {
    final group = byChipId[chipId]!;
    final merged = _mergeGroup(group);
    result.add(
      _withDiscriminator(merged, 'c$chipId'),
    );
  }
  if (unknown.isNotEmpty) {
    final merged = _mergeGroup(unknown);
    final singleId = _singleChipId(merged);
    final discriminator = singleId == null ? 'chip' : 'c$singleId';
    result.add(_withDiscriminator(merged, discriminator));
  }
  return result;
}

ReconciliationDraftOption _withDiscriminator(
  ReconciliationDraftOption option,
  String discriminator,
) {
  return ReconciliationDraftOption(
    productId: option.productId,
    normalizedPrice: option.normalizedPrice,
    priceChipId: option.priceChipId,
    chipLabel: option.chipLabel,
    sourceChipIds: option.sourceChipIds,
    sourceChipLabels: option.sourceChipLabels,
    expectedQty: option.expectedQty,
    grossAvailableQty: option.grossAvailableQty,
    keyDiscriminator: discriminator,
  );
}

ReconciliationDraftOption _mergeGroup(List<ReconciliationDraftOption> group) {
  if (group.length == 1) {
    return group.single;
  }
  var combined = group.first;
  for (var i = 1; i < group.length; i++) {
    combined = _mergePair(combined, group[i]);
  }
  return combined;
}

ReconciliationDraftOption _mergePair(
  ReconciliationDraftOption existing,
  ReconciliationDraftOption option,
) {
  final chipIdSet = <int>{};
  final labels = <String>[];
  if (existing.expectedQty != 0) {
    chipIdSet.addAll(existing.sourceChipIds);
    labels.addAll(stockedOptionLabels(existing));
  }
  if (option.expectedQty != 0) {
    chipIdSet.addAll(option.sourceChipIds);
    for (final label in stockedOptionLabels(option)) {
      if (!labels.contains(label)) {
        labels.add(label);
      }
    }
  }
  return ReconciliationDraftOption(
    productId: option.productId,
    normalizedPrice: option.normalizedPrice,
    priceChipId: _mergePriceChipId(existing, option),
    chipLabel: labels.isNotEmpty ? labels.join(', ') : existing.chipLabel,
    sourceChipIds: chipIdSet.toList()..sort(),
    sourceChipLabels: labels,
    expectedQty: existing.expectedQty + option.expectedQty,
    grossAvailableQty:
        (existing.grossAvailableQty ?? existing.expectedQty) +
        (option.grossAvailableQty ?? option.expectedQty),
  );
}

int? _singleChipId(ReconciliationDraftOption option) {
  if (option.priceChipId != null) {
    return option.priceChipId;
  }
  return option.sourceChipIds.length == 1 ? option.sourceChipIds.single : null;
}

int? _mergePriceChipId(
  ReconciliationDraftOption existing,
  ReconciliationDraftOption option,
) {
  if (existing.expectedQty == 0) {
    return option.expectedQty != 0 ? _singleChipId(option) : null;
  }
  if (option.expectedQty == 0) {
    return _singleChipId(existing);
  }

  final existingChipId = _singleChipId(existing);
  final optionChipId = _singleChipId(option);
  return existingChipId != null && existingChipId == optionChipId
      ? existingChipId
      : null;
}

List<String> stockedOptionLabels(ReconciliationDraftOption option) {
  if (option.sourceChipLabels.isNotEmpty) {
    return option.sourceChipLabels;
  }
  final fallbackLabel = option.chipLabel.trim();
  return fallbackLabel.isEmpty ? const <String>[] : <String>[fallbackLabel];
}

class ReconciliationDraft {
  ReconciliationDraft({required this.date, required this.products});

  final String date;
  final List<ReconciliationDraftProduct> products;

  factory ReconciliationDraft.fromJson(Map<String, dynamic> json) {
    final products = (json['products'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) =>
              ReconciliationDraftProduct.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    return ReconciliationDraft(
      date: json['date'] as String,
      products: products,
    );
  }
}

class ReconciliationSubmitLine {
  ReconciliationSubmitLine({
    required this.productId,
    required this.normalizedPrice,
    required this.expectedQty,
    required this.countedQty,
    required this.saleQty,
    required this.wasteQty,
    this.priceChipId,
    this.manualUnitPrice,
    this.wasteReason,
    List<ReconciliationSubmitSaleRow>? saleRows,
  }) : saleRows = saleRows ?? <ReconciliationSubmitSaleRow>[];

  final int productId;
  final int normalizedPrice;
  final int? priceChipId;
  final int expectedQty;
  final int countedQty;
  final int saleQty;
  final int wasteQty;
  final double? manualUnitPrice;
  final String? wasteReason;
  final List<ReconciliationSubmitSaleRow> saleRows;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'normalized_price': normalizedPrice,
      'price_chip_id': priceChipId,
      'expected_qty': expectedQty,
      'counted_qty': countedQty,
      'sale_qty': saleQty,
      'waste_qty': wasteQty,
      'manual_unit_price': manualUnitPrice,
      'waste_reason': wasteReason,
      'sale_rows': saleRows.map((row) => row.toJson()).toList(),
    };
  }
}

class ReconciliationSubmitSaleRow {
  ReconciliationSubmitSaleRow({
    required this.quantity,
    required this.unitPrice,
    required this.paymentMethod,
  });

  final int quantity;
  final double unitPrice;
  final String paymentMethod;

  Map<String, dynamic> toJson() {
    return {
      'quantity': quantity,
      'unit_price': unitPrice,
      'payment_method': paymentMethod,
    };
  }
}

class ReconciliationSubmitRequest {
  ReconciliationSubmitRequest({
    required this.staffName,
    required this.lines,
    this.paymentMethod,
    this.wasteReason,
  });

  final String staffName;
  final String? paymentMethod;
  final String? wasteReason;
  final List<ReconciliationSubmitLine> lines;

  Map<String, dynamic> toJson() {
    return {
      'staff_name': staffName,
      'payment_method': paymentMethod,
      'waste_reason': wasteReason,
      'lines': lines.map((line) => line.toJson()).toList(),
    };
  }
}

class ReconciliationSubmitResult {
  ReconciliationSubmitResult({
    required this.id,
    required this.date,
    required this.message,
  });

  final int id;
  final String date;
  final String message;

  factory ReconciliationSubmitResult.fromJson(Map<String, dynamic> json) {
    return ReconciliationSubmitResult(
      id: json['id'] as int,
      date: json['date'] as String,
      message: json['message'] as String,
    );
  }
}

class ReconciliationHistorySession {
  ReconciliationHistorySession({
    required this.id,
    required this.reconciliationDate,
    required this.staffName,
    required this.paymentMethod,
    required this.wasteReason,
    required this.linkedOrderRef,
    required this.lineCount,
    required this.createdAt,
  });

  final int id;
  final String reconciliationDate;
  final String staffName;
  final String paymentMethod;
  final String wasteReason;
  final String? linkedOrderRef;
  final int lineCount;
  final String createdAt;

  factory ReconciliationHistorySession.fromJson(Map<String, dynamic> json) {
    return ReconciliationHistorySession(
      id: json['id'] as int,
      reconciliationDate: json['reconciliation_date'] as String,
      staffName: json['staff_name'] as String,
      paymentMethod: (json['payment_method'] as String?) ?? '',
      wasteReason: (json['waste_reason'] as String?) ?? '',
      linkedOrderRef: json['linked_order_ref'] as String?,
      lineCount: (json['line_count'] as num?)?.toInt() ?? 0,
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}

class ReconciliationHistorySaleRow {
  ReconciliationHistorySaleRow({
    required this.id,
    required this.quantity,
    required this.unitPrice,
    required this.paymentMethod,
    required this.linkedOrderRef,
    required this.linkedPaymentRef,
    required this.isLegacy,
  });

  final int? id;
  final int quantity;
  final double? unitPrice;
  final String paymentMethod;
  final String? linkedOrderRef;
  final String? linkedPaymentRef;
  final bool isLegacy;

  factory ReconciliationHistorySaleRow.fromJson(Map<String, dynamic> json) {
    return ReconciliationHistorySaleRow(
      id: (json['id'] as num?)?.toInt(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
      paymentMethod: (json['payment_method'] as String?) ?? '',
      linkedOrderRef: json['linked_order_ref'] as String?,
      linkedPaymentRef: json['linked_payment_ref'] as String?,
      isLegacy: (json['is_legacy'] as bool?) ?? false,
    );
  }
}

class ReconciliationHistoryLine {
  ReconciliationHistoryLine({
    required this.id,
    required this.productId,
    required this.productName,
    this.priceChipId,
    this.chipLabel = 'Gia goc',
    this.normalizedPrice,
    this.sourceChipLabels = const <String>[],
    required this.expectedQty,
    required this.countedQty,
    required this.saleQty,
    required this.wasteQty,
    this.wasteReason,
    required this.manualUnitPrice,
    required this.linkedOrderItemId,
    required this.linkedStockMovementSaleId,
    required this.linkedStockMovementWasteId,
    required this.saleRows,
    this.category,
  });

  final int id;
  final int productId;
  final String productName;
  final String? category;
  final int? priceChipId;
  final String chipLabel;
  final int? normalizedPrice;
  final List<String> sourceChipLabels;
  final int expectedQty;
  final int countedQty;
  final int saleQty;
  final int wasteQty;
  final String? wasteReason;
  final double? manualUnitPrice;
  final int? linkedOrderItemId;
  final int? linkedStockMovementSaleId;
  final int? linkedStockMovementWasteId;
  final List<ReconciliationHistorySaleRow> saleRows;

  factory ReconciliationHistoryLine.fromJson(Map<String, dynamic> json) {
    final saleRows = (json['sale_rows'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) => ReconciliationHistorySaleRow.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
    return ReconciliationHistoryLine(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      productName: (json['product_name'] as String?) ?? '',
      category: json['category'] as String?,
      priceChipId: (json['price_chip_id'] as num?)?.toInt(),
      chipLabel: (json['chip_label'] as String?) ?? 'Gia goc',
      normalizedPrice: (json['normalized_price'] as num?)?.toInt(),
      sourceChipLabels:
          (json['source_chip_labels'] as List<dynamic>? ?? <dynamic>[])
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(),
      expectedQty: json['expected_qty'] as int,
      countedQty: json['counted_qty'] as int,
      saleQty: json['sale_qty'] as int,
      wasteQty: json['waste_qty'] as int,
      wasteReason: json['waste_reason'] as String?,
      manualUnitPrice: (json['manual_unit_price'] as num?)?.toDouble(),
      linkedOrderItemId: (json['linked_order_item_id'] as num?)?.toInt(),
      linkedStockMovementSaleId: (json['linked_stock_movement_sale_id'] as num?)
          ?.toInt(),
      linkedStockMovementWasteId:
          (json['linked_stock_movement_waste_id'] as num?)?.toInt(),
      saleRows: saleRows,
    );
  }
}

class ReconciliationHistoryDetail {
  ReconciliationHistoryDetail({
    required this.id,
    required this.reconciliationDate,
    required this.staffName,
    required this.paymentMethod,
    required this.wasteReason,
    required this.linkedOrderRef,
    required this.linkedPaymentRef,
    required this.createdAt,
    required this.lines,
  });

  final int id;
  final String reconciliationDate;
  final String staffName;
  final String paymentMethod;
  final String wasteReason;
  final String? linkedOrderRef;
  final String? linkedPaymentRef;
  final String createdAt;
  final List<ReconciliationHistoryLine> lines;

  factory ReconciliationHistoryDetail.fromJson(Map<String, dynamic> json) {
    final lines = (json['lines'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) =>
              ReconciliationHistoryLine.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    return ReconciliationHistoryDetail(
      id: json['id'] as int,
      reconciliationDate: json['reconciliation_date'] as String,
      staffName: json['staff_name'] as String,
      paymentMethod: (json['payment_method'] as String?) ?? '',
      wasteReason: (json['waste_reason'] as String?) ?? '',
      linkedOrderRef: json['linked_order_ref'] as String?,
      linkedPaymentRef: json['linked_payment_ref'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      lines: lines,
    );
  }
}
