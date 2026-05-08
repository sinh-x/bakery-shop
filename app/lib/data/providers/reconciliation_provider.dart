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
  ReconciliationSaleRowError({
    this.quantity,
    this.unitPrice,
    this.paymentMethod,
  });

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
    Map<String, int>? countedQtyByOption,
    Map<String, int>? wasteQtyByOption,
    Map<String, String>? wasteReasonByOption,
    Map<String, List<ReconciliationSaleRowInput>>? saleRowsByOption,
    Map<String, String>? optionErrors,
    Map<String, List<ReconciliationSaleRowError>>? saleRowErrorsByOption,
  }) : countedQtyByOption = countedQtyByOption ?? <String, int>{},
       wasteQtyByOption = wasteQtyByOption ?? <String, int>{},
       wasteReasonByOption = wasteReasonByOption ?? <String, String>{},
       saleRowsByOption =
           saleRowsByOption ?? <String, List<ReconciliationSaleRowInput>>{},
       optionErrors = optionErrors ?? <String, String>{},
       saleRowErrorsByOption =
           saleRowErrorsByOption ??
           <String, List<ReconciliationSaleRowError>>{};

  final bool isLoading;
  final bool isSubmitting;
  final String? submitSuccessMessage;
  final int? lastSubmittedSessionId;
  final String? errorMessage;
  final ReconciliationDraft? draft;
  final String? paymentMethod;
  final String wasteReason;
  final Map<String, int> countedQtyByOption;
  final Map<String, int> wasteQtyByOption;
  final Map<String, String> wasteReasonByOption;
  final Map<String, List<ReconciliationSaleRowInput>> saleRowsByOption;
  final Map<String, String> optionErrors;
  final Map<String, List<ReconciliationSaleRowError>> saleRowErrorsByOption;

  bool get hasSale => saleRowsByOption.values.any(
    (rows) => rows.any((row) => row.quantity > 0),
  );
  bool get hasWaste => wasteQtyByOption.values.any((value) => value > 0);

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
    Map<String, int>? countedQtyByOption,
    Map<String, int>? wasteQtyByOption,
    Map<String, String>? wasteReasonByOption,
    Map<String, List<ReconciliationSaleRowInput>>? saleRowsByOption,
    Map<String, String>? optionErrors,
    Map<String, List<ReconciliationSaleRowError>>? saleRowErrorsByOption,
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
      countedQtyByOption: countedQtyByOption ?? this.countedQtyByOption,
      wasteQtyByOption: wasteQtyByOption ?? this.wasteQtyByOption,
      wasteReasonByOption: wasteReasonByOption ?? this.wasteReasonByOption,
      saleRowsByOption: saleRowsByOption ?? this.saleRowsByOption,
      optionErrors: clearInlineErrors
          ? <String, String>{}
          : (optionErrors ?? this.optionErrors),
      saleRowErrorsByOption: clearInlineErrors
          ? <String, List<ReconciliationSaleRowError>>{}
          : (saleRowErrorsByOption ?? this.saleRowErrorsByOption),
    );
  }
}

String reconciliationOptionKey(int productId, int? priceChipId) {
  return '$productId:$priceChipId';
}

String _normalizeOptionKey(Object optionKeyOrProductId) {
  if (optionKeyOrProductId is String) {
    return optionKeyOrProductId;
  }
  if (optionKeyOrProductId is int) {
    return reconciliationOptionKey(optionKeyOrProductId, null);
  }
  throw ArgumentError('Invalid option key: $optionKeyOrProductId');
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
      final counted = <String, int>{};
      final waste = <String, int>{};
      final wasteReasons = <String, String>{};
      final saleRows = <String, List<ReconciliationSaleRowInput>>{};
      for (final product in draft.products) {
        for (final option in product.options) {
          final key = reconciliationOptionKey(
            option.productId,
            option.priceChipId,
          );
          counted[key] = option.expectedQty;
          waste[key] = 0;
          wasteReasons[key] = '';
          saleRows[key] = <ReconciliationSaleRowInput>[];
        }
      }

      state = state.copyWith(
        isLoading: false,
        draft: draft,
        countedQtyByOption: counted,
        wasteQtyByOption: waste,
        wasteReasonByOption: wasteReasons,
        saleRowsByOption: saleRows,
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

  void setCountedQty(Object optionKeyOrProductId, int value) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    final next = Map<String, int>.from(state.countedQtyByOption);
    next[optionKey] = value;
    state = state.copyWith(
      countedQtyByOption: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void setWasteQty(Object optionKeyOrProductId, int value) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    final next = Map<String, int>.from(state.wasteQtyByOption);
    next[optionKey] = value;
    state = state.copyWith(
      wasteQtyByOption: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void addSaleRow(Object optionKeyOrProductId) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    final next = Map<String, List<ReconciliationSaleRowInput>>.from(
      state.saleRowsByOption,
    );
    final rows = List<ReconciliationSaleRowInput>.from(next[optionKey] ?? []);
    rows.add(ReconciliationSaleRowInput());
    next[optionKey] = rows;
    state = state.copyWith(
      saleRowsByOption: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void removeSaleRow(Object optionKeyOrProductId, int rowIndex) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    final next = Map<String, List<ReconciliationSaleRowInput>>.from(
      state.saleRowsByOption,
    );
    final rows = List<ReconciliationSaleRowInput>.from(next[optionKey] ?? []);
    if (rowIndex < 0 || rowIndex >= rows.length) {
      return;
    }
    rows.removeAt(rowIndex);
    next[optionKey] = rows;
    state = state.copyWith(
      saleRowsByOption: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void setSaleRowQty(Object optionKeyOrProductId, int rowIndex, int value) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    _updateSaleRow(optionKey, rowIndex, (row) => row.copyWith(quantity: value));
  }

  void setSaleRowUnitPrice(
    Object optionKeyOrProductId,
    int rowIndex,
    String value,
  ) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    _updateSaleRow(
      optionKey,
      rowIndex,
      (row) => row.copyWith(unitPrice: value),
    );
  }

  void setSaleRowPaymentMethod(
    Object optionKeyOrProductId,
    int rowIndex,
    String? method,
  ) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    _updateSaleRow(
      optionKey,
      rowIndex,
      (row) => row.copyWith(paymentMethod: method),
    );
  }

  void fillSaleRowPriceFromChip(
    Object optionKeyOrProductId,
    int rowIndex,
    double unitPrice,
  ) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    setSaleRowUnitPrice(optionKey, rowIndex, unitPrice.toStringAsFixed(0));
  }

  void _updateSaleRow(
    String optionKey,
    int rowIndex,
    ReconciliationSaleRowInput Function(ReconciliationSaleRowInput row) updater,
  ) {
    final next = Map<String, List<ReconciliationSaleRowInput>>.from(
      state.saleRowsByOption,
    );
    final rows = List<ReconciliationSaleRowInput>.from(next[optionKey] ?? []);
    if (rowIndex < 0 || rowIndex >= rows.length) {
      return;
    }
    rows[rowIndex] = updater(rows[rowIndex]);
    next[optionKey] = rows;
    state = state.copyWith(
      saleRowsByOption: next,
      clearInlineErrors: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
      clearLastSubmittedSessionId: true,
    );
  }

  void setWasteReasonForOption(Object optionKeyOrProductId, String reason) {
    final optionKey = _normalizeOptionKey(optionKeyOrProductId);
    final next = Map<String, String>.from(state.wasteReasonByOption);
    next[optionKey] = reason;
    state = state.copyWith(
      wasteReasonByOption: next,
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
        optionErrors: validation.optionErrors,
        saleRowErrorsByOption: validation.saleRowErrorsByOption,
      );
      return false;
    }

    final lines = draft.products.expand((product) {
      return product.options.map((option) {
        final optionKey = reconciliationOptionKey(
          product.productId,
          option.priceChipId,
        );
        final rows =
            state.saleRowsByOption[optionKey] ??
            const <ReconciliationSaleRowInput>[];
        final activeRows = rows.where((row) => row.quantity > 0).toList();
        final saleQty = activeRows.fold<int>(
          0,
          (sum, row) => sum + row.quantity,
        );
        final wasteQty = state.wasteQtyByOption[optionKey] ?? 0;
        return ReconciliationSubmitLine(
          productId: product.productId,
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
                  unitPrice: double.tryParse(row.unitPrice.trim()) ?? 0,
                  paymentMethod: row.paymentMethod!,
                ),
              )
              .toList(),
        );
      });
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

  _ValidationResult? _validate(
    ReconciliationState currentState,
    String staffName,
  ) {
    if (staffName.isEmpty) {
      return _ValidationResult(
        'Vui lòng chọn tên nhân viên trong Cài đặt trước khi đối soát',
      );
    }
    final draft = currentState.draft;
    if (draft == null) {
      return _ValidationResult('Chưa có dữ liệu đối soát');
    }

    final productErrors = <String, String>{};
    final rowErrors = <String, List<ReconciliationSaleRowError>>{};

    for (final product in draft.products) {
      for (final option in product.options) {
        final optionKey = reconciliationOptionKey(
          product.productId,
          option.priceChipId,
        );
        final counted = currentState.countedQtyByOption[optionKey] ?? 0;
        final rows =
            currentState.saleRowsByOption[optionKey] ??
            const <ReconciliationSaleRowInput>[];
        final sale = rows.fold<int>(0, (sum, row) => sum + row.quantity);
        final waste = currentState.wasteQtyByOption[optionKey] ?? 0;
        if (counted < 0 || sale < 0 || waste < 0) {
          return _ValidationResult('Số lượng không được âm');
        }
        if (counted > option.expectedQty) {
          productErrors[optionKey] =
              'Số đếm thực tế không được lớn hơn số tồn dự kiến';
          continue;
        }

        final missing = option.expectedQty - counted;
        if (missing < 0) {
          productErrors[optionKey] =
              'Số đếm thực tế không được lớn hơn số tồn dự kiến';
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
            final parsedPrice = double.tryParse(row.unitPrice.trim());
            if (parsedPrice == null || parsedPrice <= 0) {
              priceError = 'Đơn giá phải lớn hơn 0';
            }
            if (row.paymentMethod != 'cash' &&
                row.paymentMethod != 'transfer') {
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
      return _ValidationResult(
        'Vui lòng kiểm tra dữ liệu đối soát',
        optionErrors: productErrors,
        saleRowErrorsByOption: rowErrors,
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
    this.optionErrors = const <String, String>{},
    this.saleRowErrorsByOption =
        const <String, List<ReconciliationSaleRowError>>{},
  });

  final String message;
  final Map<String, String> optionErrors;
  final Map<String, List<ReconciliationSaleRowError>> saleRowErrorsByOption;
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
