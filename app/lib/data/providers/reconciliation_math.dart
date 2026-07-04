import '../api/reconciliation_service.dart';
import 'reconciliation_state.dart';

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
    return product.options.where((option) => option.expectedQty > 0).map((
      option,
    ) {
      final optionKey = reconciliationOptionKey(
        product.productId,
        option.normalizedPrice,
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
