import '../api/reconciliation_models.dart';
import 'reconciliation_state.dart';

/// Discriminator value stamped on the base-price bucket of a collision group
/// by [mergeOptionsByNormalizedPrice]. Consumed via
/// [ReconciliationDraftOption.isBasePriceOption] instead of the raw literal
/// (DG-413 CQ-6).
const String kBasePriceDiscriminator = 'base';

/// Prefix used by [mergeOptionsByNormalizedPrice] for a resolved chip bucket
/// discriminator (`c<chipId>`). Consumed via
/// [ReconciliationDraftOption.isBasePriceOption] instead of the raw literal
/// (DG-413 CQ-6).
const String kChipPriceDiscriminatorPrefix = 'c';

/// Groups raw reconciliation options by normalized price and merges each
/// group, splitting base-price vs chip-price buckets when they collide at
/// the same normalized price so the backend per-`price_chip_id`
/// `expected_qty` comparison still matches (DG-413).
///
/// Relocated from `reconciliation_models.dart` to `reconciliation_math.dart`
/// in DG-413 review cycle 4 (CQ-10): this is reconciliation business logic,
/// not a pure data-class concern, and `reconciliation_math.dart` is the
/// established home for reconciliation math (it already hosts
/// `buildSubmitLines`). `reconciliation_models.dart` is now pure data
/// classes.
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
    result.add(
      _withDiscriminator(_mergeGroup(baseOptions), kBasePriceDiscriminator),
    );
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
///
/// Options whose chip id cannot be resolved (`priceChipId == null` and
/// `sourceChipIds.length != 1`) are rejected loudly via [StateError] rather
/// than silently merging into a `price_chip_id: null` line that would
/// re-collide with the base bucket (DG-413 CQ-8). The current backend always
/// emits `price_chip_id` for chip options, so this branch is unreachable in
/// production; failing loudly surfaces payload drift early instead of
/// silently corrupting the submit request.
List<ReconciliationDraftOption> _splitChipOptionsByChipId(
  List<ReconciliationDraftOption> chipOptions,
) {
  // Group by the resolved chip id. Options whose chip id cannot be resolved
  // are rejected loudly (DG-413 CQ-8): a null-chip merged option would
  // re-collide with the base bucket in buildSubmitLines. The backend payload
  // always sets price_chip_id for chip options, so this guard fires only on
  // payload drift.
  final byChipId = <int, List<ReconciliationDraftOption>>{};
  final order = <int>[];
  for (final option in chipOptions) {
    final chipId = _singleChipId(option);
    if (chipId == null) {
      throw StateError(
        'DG-413 CQ-8: cannot resolve a single price_chip_id for a chip '
        'option colliding at the same normalized price as a base-price '
        'option (product_id=${option.productId}, '
        'normalized_price=${option.normalizedPrice}, '
        'price_chip_id=${option.priceChipId}, '
        'source_chip_ids=${option.sourceChipIds}). Merging it would emit a '
        'null-chip submit line that re-collides with the base bucket.',
      );
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
      _withDiscriminator(merged, '$kChipPriceDiscriminatorPrefix$chipId'),
    );
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

class ReconciliationValidationResult {
  ReconciliationValidationResult(
    this.message, {
    this.optionErrors = const <String, String>{},
    this.saleRowErrorsByOption =
        const <String, List<ReconciliationSaleRowError>>{},
  });

  final String message;
  final Map<String, String> optionErrors;
  final Map<String, List<ReconciliationSaleRowError>> saleRowErrorsByOption;
}

List<ReconciliationSubmitLine> buildSubmitLines(ReconciliationState state) {
  final draft = state.draft;
  if (draft == null) {
    return const <ReconciliationSubmitLine>[];
  }

  return draft.products.expand((product) {
    return product.options.where((option) => option.expectedQty != 0).map((
      option,
    ) {
      final optionKey = reconciliationOptionKey(
        product.productId,
        option.normalizedPrice,
        discriminator: option.keyDiscriminator,
      );
      final rows =
          state.saleRowsByOption[optionKey] ??
          const <ReconciliationSaleRowInput>[];
      final activeRows = rows.where((row) => row.quantity > 0).toList();
      final saleQty = activeRows.fold<int>(0, (sum, row) => sum + row.quantity);
      final wasteQty = state.wasteQtyByOption[optionKey] ?? 0;
      return ReconciliationSubmitLine(
        productId: product.productId,
        normalizedPrice: option.normalizedPrice,
        priceChipId: option.priceChipId,
        expectedQty: option.expectedQty,
        countedQty: state.countedQtyByOption[optionKey] ?? 0,
        saleQty: saleQty,
        wasteQty: wasteQty,
        manualUnitPrice: null,
        wasteReason: wasteQty > 0
            ? state.wasteReasonByOption[optionKey]?.trim()
            : null,
        saleRows: activeRows
            .map(
              (row) => ReconciliationSubmitSaleRow(
                quantity: row.quantity,
                unitPrice: row.unitPrice ?? 0,
                paymentMethod: row.paymentMethod!,
              ),
            )
            .toList(),
      );
    });
  }).toList();
}

bool hasReconciliationOptionIssue({
  required ReconciliationDraftOption option,
  required int counted,
  required List<ReconciliationSaleRowInput> saleRows,
  required int waste,
  required String wasteReason,
}) {
  final sale = saleRows.fold<int>(0, (sum, row) => sum + row.quantity);
  if (counted < 0 || sale < 0 || waste < 0) {
    return true;
  }

  final missing = option.expectedQty - counted;

  // Surplus case (counted > expected): backend converts the surplus into a
  // restock inflow after netting any negative balance. Sale and waste rows
  // must be empty because there is no "missing" stock to account for.
  if (missing < 0) {
    return sale > 0 || waste > 0;
  }

  if (waste > missing) {
    return true;
  }
  if (missing > 0 && sale + waste != missing) {
    return true;
  }

  for (final row in saleRows) {
    if (row.quantity < 0) {
      return true;
    }
    if (row.quantity > 0) {
      final price = row.unitPrice;
      if (price == null || price <= 0) {
        return true;
      }
      if (row.paymentMethod != 'cash' && row.paymentMethod != 'transfer') {
        return true;
      }
    }
  }

  return waste > 0 && wasteReason.trim().isEmpty;
}

ReconciliationValidationResult? validateReconciliationState(
  ReconciliationState currentState,
  String staffName,
) {
  if (staffName.isEmpty) {
    return ReconciliationValidationResult(
      'Vui lòng chọn tên nhân viên trong Cài đặt trước khi đối soát',
    );
  }
  final draft = currentState.draft;
  if (draft == null) {
    return ReconciliationValidationResult('Chưa có dữ liệu đối soát');
  }

  final productErrors = <String, String>{};
  final rowErrors = <String, List<ReconciliationSaleRowError>>{};

  for (final product in draft.products) {
    for (final option in product.options) {
      final optionKey = reconciliationOptionKey(
        product.productId,
        option.normalizedPrice,
        discriminator: option.keyDiscriminator,
      );
      final counted = currentState.countedQtyByOption[optionKey] ?? 0;
      final rows =
          currentState.saleRowsByOption[optionKey] ??
          const <ReconciliationSaleRowInput>[];
      final sale = rows.fold<int>(0, (sum, row) => sum + row.quantity);
      final waste = currentState.wasteQtyByOption[optionKey] ?? 0;
      if (counted < 0 || sale < 0 || waste < 0) {
        return ReconciliationValidationResult('Số lượng không được âm');
      }

      final missing = option.expectedQty - counted;

      // Surplus case (counted > expected): backend converts the surplus into a
      // restock inflow. Sale and waste rows must be empty — there is no missing
      // stock to split between sale and waste.
      if (missing < 0) {
        if (sale > 0 || waste > 0) {
          productErrors[optionKey] =
              'Số đếm lớn hơn tồn dự kiến sẽ tự nhập bù. Vui lòng xoá dòng bán và hao hụt.';
          continue;
        }
        continue;
      }

      if (waste > missing) {
        productErrors[optionKey] =
            'Số hao hụt vượt quá số thiếu. Vui lòng vào màn hình \'Nhập hàng\' để bổ sung tồn kho trước.';
        continue;
      }
      if (missing > 0 && sale + waste != missing) {
        productErrors[optionKey] =
            'Sản phẩm thiếu phải tách đúng: bán + hao hụt = số thiếu';
      }

      final itemErrors = <ReconciliationSaleRowError>[];
      for (final row in rows) {
        String? qtyError;
        String? priceError;
        String? methodError;
        if (row.quantity < 0) {
          qtyError = 'Số lượng không được âm';
        }
        if (row.quantity > 0) {
          final parsedPrice = row.unitPrice;
          if (parsedPrice == null || parsedPrice <= 0) {
            priceError = 'Đơn giá phải lớn hơn 0';
          }
          if (row.paymentMethod != 'cash' && row.paymentMethod != 'transfer') {
            methodError = 'Chọn phương thức';
          }
        }
        itemErrors.add(
          ReconciliationSaleRowError(
            quantity: qtyError,
            unitPrice: priceError,
            paymentMethod: methodError,
          ),
        );
      }
      if (itemErrors.any((error) => error.hasError)) {
        rowErrors[optionKey] = itemErrors;
      }

      if (waste > 0) {
        final reason = (currentState.wasteReasonByOption[optionKey] ?? '')
            .trim();
        if (reason.isEmpty) {
          productErrors[optionKey] = 'Sản phẩm có hao hụt phải nhập lý do';
        }
      }
    }
  }

  if (productErrors.isNotEmpty || rowErrors.isNotEmpty) {
    return ReconciliationValidationResult(
      'Vui lòng kiểm tra dữ liệu đối soát',
      optionErrors: productErrors,
      saleRowErrorsByOption: rowErrors,
    );
  }

  return null;
}