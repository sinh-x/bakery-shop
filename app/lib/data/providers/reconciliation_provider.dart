import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/events_provider.dart';
import '../../providers/products_provider.dart';
import '../api/reconciliation_service.dart';

class ReconciliationSaleRowInput {
  ReconciliationSaleRowInput({
    this.quantity = 0,
    this.unitPrice = '',
    this.paymentMethod,
  });

  final int quantity;
  final String unitPrice;
  final String? paymentMethod;

  ReconciliationSaleRowInput copyWith({
    int? quantity,
    String? unitPrice,
    String? paymentMethod,
    bool clearPaymentMethod = false,
  }) {
    return ReconciliationSaleRowInput(
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      paymentMethod: clearPaymentMethod
          ? null
          : (paymentMethod ?? this.paymentMethod),
    );
  }
}

class ReconciliationSaleRowError {
  ReconciliationSaleRowError({this.quantity, this.unitPrice, this.paymentMethod});

  final String? quantity;
  final String? unitPrice;
  final String? paymentMethod;

  bool get hasError =>
      quantity != null || unitPrice != null || paymentMethod != null;
}

class ReconciliationState {
  ReconciliationState({
    this.isLoading = false,
    this.isSubmitting = false,
    this.submitSuccessMessage,
    this.lastSubmittedSessionId,
    this.errorMessage,
    this.draft,
    this.paymentMethod,
    this.wasteReason = '',
    Map<int, int>? countedQtyByProduct,
    Map<int, int>? wasteQtyByProduct,
    Map<int, String>? wasteReasonByProduct,
    Map<int, List<ReconciliationSaleRowInput>>? saleRowsByProduct,
    Map<int, String>? productErrors,
    Map<int, List<ReconciliationSaleRowError>>? saleRowErrorsByProduct,
  }) : countedQtyByProduct = countedQtyByProduct ?? <int, int>{},
       wasteQtyByProduct = wasteQtyByProduct ?? <int, int>{},
       wasteReasonByProduct = wasteReasonByProduct ?? <int, String>{},
       saleRowsByProduct = saleRowsByProduct ??
           <int, List<ReconciliationSaleRowInput>>{},
       productErrors = productErrors ?? <int, String>{},
       saleRowErrorsByProduct =
           saleRowErrorsByProduct ?? <int, List<ReconciliationSaleRowError>>{};

  final bool isLoading;
  final bool isSubmitting;
  final String? submitSuccessMessage;
  final int? lastSubmittedSessionId;
  final String? errorMessage;
  final ReconciliationDraft? draft;
  final String? paymentMethod;
  final String wasteReason;
  final Map<int, int> countedQtyByProduct;
  final Map<int, int> wasteQtyByProduct;
  final Map<int, String> wasteReasonByProduct;
  final Map<int, List<ReconciliationSaleRowInput>> saleRowsByProduct;
  final Map<int, String> productErrors;
  final Map<int, List<ReconciliationSaleRowError>> saleRowErrorsByProduct;

  bool get hasSale => saleRowsByProduct.values.any(
    (rows) => rows.any((row) => row.quantity > 0),
  );
  bool get hasWaste => wasteQtyByProduct.values.any((value) => value > 0);

  ReconciliationState copyWith({
    bool? isLoading,
    bool? isSubmitting,
    String? submitSuccessMessage,
    bool clearSubmitSuccessMessage = false,
    int? lastSubmittedSessionId,
    bool clearLastSubmittedSessionId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    ReconciliationDraft? draft,
    String? paymentMethod,
    bool clearPaymentMethod = false,
    String? wasteReason,
    Map<int, int>? countedQtyByProduct,
    Map<int, int>? wasteQtyByProduct,
    Map<int, String>? wasteReasonByProduct,
    Map<int, List<ReconciliationSaleRowInput>>? saleRowsByProduct,
    Map<int, String>? productErrors,
    Map<int, List<ReconciliationSaleRowError>>? saleRowErrorsByProduct,
    bool clearInlineErrors = false,
  }) {
    return ReconciliationState(
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitSuccessMessage: clearSubmitSuccessMessage
          ? null
          : (submitSuccessMessage ?? this.submitSuccessMessage),
      lastSubmittedSessionId: clearLastSubmittedSessionId
          ? null
          : (lastSubmittedSessionId ?? this.lastSubmittedSessionId),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      draft: draft ?? this.draft,
      paymentMethod: clearPaymentMethod
          ? null
          : (paymentMethod ?? this.paymentMethod),
      wasteReason: wasteReason ?? this.wasteReason,
      countedQtyByProduct: countedQtyByProduct ?? this.countedQtyByProduct,
      wasteQtyByProduct: wasteQtyByProduct ?? this.wasteQtyByProduct,
      wasteReasonByProduct:
          wasteReasonByProduct ?? this.wasteReasonByProduct,
      saleRowsByProduct: saleRowsByProduct ?? this.saleRowsByProduct,
      productErrors: clearInlineErrors
          ? <int, String>{}
          : (productErrors ?? this.productErrors),
      saleRowErrorsByProduct: clearInlineErrors
          ? <int, List<ReconciliationSaleRowError>>{}
          : (saleRowErrorsByProduct ?? this.saleRowErrorsByProduct),
    );
  }
}

class ReconciliationNotifier extends Notifier<ReconciliationState> {
  @override
  ReconciliationState build() {
    return ReconciliationState();
  }

  Future<void> loadDraft() async {
    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
    try {
      final draft = await ref.read(reconciliationServiceProvider).getDraft();
      final counted = <int, int>{};
      final waste = <int, int>{};
      final wasteReasons = <int, String>{};
      final saleRows = <int, List<ReconciliationSaleRowInput>>{};
      for (final product in draft.products) {
        counted[product.productId] = product.expectedQty;
        waste[product.productId] = 0;
        wasteReasons[product.productId] = '';
        saleRows[product.productId] = <ReconciliationSaleRowInput>[];
      }

      state = state.copyWith(
        isLoading: false,
        draft: draft,
        countedQtyByProduct: counted,
        wasteQtyByProduct: waste,
        wasteReasonByProduct: wasteReasons,
        saleRowsByProduct: saleRows,
        clearInlineErrors: true,
        clearPaymentMethod: true,
        wasteReason: '',
        clearLastSubmittedSessionId: true,
      );
    } on DioException catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _resolveDioError(error),
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải dữ liệu đối soát',
      );
    }
  }

  void setCountedQty(int productId, int value) {
    final next = Map<int, int>.from(state.countedQtyByProduct);
    next[productId] = value;
    state = state.copyWith(
      countedQtyByProduct: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void setWasteQty(int productId, int value) {
    final next = Map<int, int>.from(state.wasteQtyByProduct);
    next[productId] = value;
    state = state.copyWith(
      wasteQtyByProduct: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void addSaleRow(int productId) {
    final next = Map<int, List<ReconciliationSaleRowInput>>.from(
      state.saleRowsByProduct,
    );
    final rows = List<ReconciliationSaleRowInput>.from(next[productId] ?? []);
    rows.add(ReconciliationSaleRowInput());
    next[productId] = rows;
    state = state.copyWith(
      saleRowsByProduct: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void removeSaleRow(int productId, int rowIndex) {
    final next = Map<int, List<ReconciliationSaleRowInput>>.from(
      state.saleRowsByProduct,
    );
    final rows = List<ReconciliationSaleRowInput>.from(next[productId] ?? []);
    if (rowIndex < 0 || rowIndex >= rows.length) {
      return;
    }
    rows.removeAt(rowIndex);
    next[productId] = rows;
    state = state.copyWith(
      saleRowsByProduct: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void setSaleRowQty(int productId, int rowIndex, int value) {
    _updateSaleRow(
      productId,
      rowIndex,
      (row) => row.copyWith(quantity: value),
    );
  }

  void setSaleRowUnitPrice(int productId, int rowIndex, String value) {
    _updateSaleRow(
      productId,
      rowIndex,
      (row) => row.copyWith(unitPrice: value),
    );
  }

  void setSaleRowPaymentMethod(int productId, int rowIndex, String? method) {
    _updateSaleRow(
      productId,
      rowIndex,
      (row) => row.copyWith(paymentMethod: method),
    );
  }

  void fillSaleRowPriceFromChip(int productId, int rowIndex, double unitPrice) {
    setSaleRowUnitPrice(productId, rowIndex, unitPrice.toStringAsFixed(0));
  }

  void _updateSaleRow(
    int productId,
    int rowIndex,
    ReconciliationSaleRowInput Function(ReconciliationSaleRowInput row) updater,
  ) {
    final next = Map<int, List<ReconciliationSaleRowInput>>.from(
      state.saleRowsByProduct,
    );
    final rows = List<ReconciliationSaleRowInput>.from(next[productId] ?? []);
    if (rowIndex < 0 || rowIndex >= rows.length) {
      return;
    }
    rows[rowIndex] = updater(rows[rowIndex]);
    next[productId] = rows;
    state = state.copyWith(
      saleRowsByProduct: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void setWasteReasonForProduct(int productId, String reason) {
    final next = Map<int, String>.from(state.wasteReasonByProduct);
    next[productId] = reason;
    state = state.copyWith(
      wasteReasonByProduct: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void setPaymentMethod(String? method) {
    state = state.copyWith(
      paymentMethod: method,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void setWasteReason(String value) {
    state = state.copyWith(
      wasteReason: value,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  Future<bool> submit() async {
    final draft = state.draft;
    final staffName = ref.read(loggedByProvider).trim();
    if (draft == null) {
      state = state.copyWith(errorMessage: 'Chưa có dữ liệu đối soát để gửi');
      return false;
    }

    final validation = _validate(state, staffName);
    if (validation != null) {
      state = state.copyWith(
        errorMessage: validation.message,
        productErrors: validation.productErrors,
        saleRowErrorsByProduct: validation.saleRowErrorsByProduct,
      );
      return false;
    }

    final lines = draft.products.map((product) {
      final rows = state.saleRowsByProduct[product.productId] ??
          const <ReconciliationSaleRowInput>[];
      final activeRows = rows.where((row) => row.quantity > 0).toList();
      final saleQty = activeRows.fold<int>(0, (sum, row) => sum + row.quantity);
      final wasteQty = state.wasteQtyByProduct[product.productId] ?? 0;
      return ReconciliationSubmitLine(
        productId: product.productId,
        expectedQty: product.expectedQty,
        countedQty: state.countedQtyByProduct[product.productId] ?? 0,
        saleQty: saleQty,
        wasteQty: wasteQty,
        manualUnitPrice: null,
        wasteReason: wasteQty > 0 ? state.wasteReasonByProduct[product.productId]?.trim() : null,
        saleRows: activeRows
            .map(
              (row) => ReconciliationSubmitSaleRow(
                quantity: row.quantity,
                unitPrice: double.parse(row.unitPrice.trim()),
                paymentMethod: row.paymentMethod!,
              ),
            )
            .toList(),
      );
    }).toList();

    state = state.copyWith(
      isSubmitting: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );

    try {
      final request = ReconciliationSubmitRequest(
        staffName: staffName,
        paymentMethod: null,
        wasteReason: state.hasWaste ? state.wasteReason.trim() : null,
        lines: lines,
      );

      final result = await ref
          .read(reconciliationServiceProvider)
          .submit(request);
      ref.invalidate(productsProvider);
      await loadDraft();
      state = state.copyWith(
        submitSuccessMessage: result.message,
        lastSubmittedSessionId: result.id,
        isSubmitting: false,
      );
      return true;
    } on DioException catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _resolveDioError(error),
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Gửi đối soát thất bại, vui lòng thử lại',
      );
      return false;
    }
  }

  _ValidationResult? _validate(ReconciliationState currentState, String staffName) {
    if (staffName.isEmpty) {
      return _ValidationResult('Vui lòng chọn tên nhân viên trong Cài đặt trước khi đối soát');
    }
    final draft = currentState.draft;
    if (draft == null) {
      return _ValidationResult('Chưa có dữ liệu đối soát');
    }

    final productErrors = <int, String>{};
    final rowErrors = <int, List<ReconciliationSaleRowError>>{};

    for (final product in draft.products) {
      final counted = currentState.countedQtyByProduct[product.productId] ?? 0;
      final rows = currentState.saleRowsByProduct[product.productId] ??
          const <ReconciliationSaleRowInput>[];
      final sale = rows.fold<int>(0, (sum, row) => sum + row.quantity);
      final waste = currentState.wasteQtyByProduct[product.productId] ?? 0;
      if (counted < 0 || sale < 0 || waste < 0) {
        return _ValidationResult('Số lượng không được âm');
      }
      if (counted > product.expectedQty) {
        productErrors[product.productId] =
            'Số đếm thực tế không được lớn hơn số tồn dự kiến';
        continue;
      }

      final missing = product.expectedQty - counted;
      if (missing < 0) {
        productErrors[product.productId] =
            'Số đếm thực tế không được lớn hơn số tồn dự kiến';
        continue;
      }
      if (waste > missing) {
        productErrors[product.productId] =
            'Số hao hụt vượt quá số thiếu. Vui lòng vào màn hình \'Nhập hàng\' để bổ sung tồn kho trước.';
        continue;
      }
      if (missing > 0 && sale + waste != missing) {
        productErrors[product.productId] =
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
          final parsedPrice = double.tryParse(row.unitPrice.trim());
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
        rowErrors[product.productId] = itemErrors;
      }

      if (waste > 0) {
        final reason = (currentState.wasteReasonByProduct[product.productId] ?? '').trim();
        if (reason.isEmpty) {
          productErrors[product.productId] = 'Sản phẩm có hao hụt phải nhập lý do';
        }
      }
    }

    if (productErrors.isNotEmpty || rowErrors.isNotEmpty) {
      return _ValidationResult(
        'Vui lòng kiểm tra dữ liệu đối soát',
        productErrors: productErrors,
        saleRowErrorsByProduct: rowErrors,
      );
    }

    return null;
  }

  String _resolveDioError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Không thể kết nối máy chủ';
    }
    return 'Có lỗi xảy ra khi gửi đối soát';
  }
}

class _ValidationResult {
  _ValidationResult(
    this.message, {
    this.productErrors = const <int, String>{},
    this.saleRowErrorsByProduct = const <int, List<ReconciliationSaleRowError>>{},
  });

  final String message;
  final Map<int, String> productErrors;
  final Map<int, List<ReconciliationSaleRowError>> saleRowErrorsByProduct;
}

final reconciliationProvider =
    NotifierProvider<ReconciliationNotifier, ReconciliationState>(
      ReconciliationNotifier.new,
    );

final reconciliationHistoryListProvider =
    FutureProvider<List<ReconciliationHistorySession>>((ref) async {
      return ref.read(reconciliationServiceProvider).getHistorySessions();
    });

final reconciliationHistoryDetailProvider =
    FutureProvider.family<ReconciliationHistoryDetail, int>((
      ref,
      sessionId,
    ) async {
      return ref
          .read(reconciliationServiceProvider)
          .getHistoryDetail(sessionId);
    });
