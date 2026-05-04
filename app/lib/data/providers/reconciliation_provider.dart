import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/events_provider.dart';
import '../../providers/products_provider.dart';
import '../api/reconciliation_service.dart';

class ReconciliationState {
  ReconciliationState({
    this.isLoading = false,
    this.isSubmitting = false,
    this.submitSuccessMessage,
    this.errorMessage,
    this.draft,
    this.paymentMethod,
    this.wasteReason = '',
    Map<int, int>? countedQtyByProduct,
    Map<int, int>? saleQtyByProduct,
    Map<int, int>? wasteQtyByProduct,
    Map<int, String>? manualUnitPriceByProduct,
  }) : countedQtyByProduct = countedQtyByProduct ?? <int, int>{},
       saleQtyByProduct = saleQtyByProduct ?? <int, int>{},
       wasteQtyByProduct = wasteQtyByProduct ?? <int, int>{},
       manualUnitPriceByProduct = manualUnitPriceByProduct ?? <int, String>{};

  final bool isLoading;
  final bool isSubmitting;
  final String? submitSuccessMessage;
  final String? errorMessage;
  final ReconciliationDraft? draft;
  final String? paymentMethod;
  final String wasteReason;
  final Map<int, int> countedQtyByProduct;
  final Map<int, int> saleQtyByProduct;
  final Map<int, int> wasteQtyByProduct;
  final Map<int, String> manualUnitPriceByProduct;

  bool get hasSale => saleQtyByProduct.values.any((value) => value > 0);
  bool get hasWaste => wasteQtyByProduct.values.any((value) => value > 0);

  ReconciliationState copyWith({
    bool? isLoading,
    bool? isSubmitting,
    String? submitSuccessMessage,
    bool clearSubmitSuccessMessage = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    ReconciliationDraft? draft,
    String? paymentMethod,
    bool clearPaymentMethod = false,
    String? wasteReason,
    Map<int, int>? countedQtyByProduct,
    Map<int, int>? saleQtyByProduct,
    Map<int, int>? wasteQtyByProduct,
    Map<int, String>? manualUnitPriceByProduct,
  }) {
    return ReconciliationState(
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitSuccessMessage: clearSubmitSuccessMessage
          ? null
          : (submitSuccessMessage ?? this.submitSuccessMessage),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      draft: draft ?? this.draft,
      paymentMethod: clearPaymentMethod
          ? null
          : (paymentMethod ?? this.paymentMethod),
      wasteReason: wasteReason ?? this.wasteReason,
      countedQtyByProduct: countedQtyByProduct ?? this.countedQtyByProduct,
      saleQtyByProduct: saleQtyByProduct ?? this.saleQtyByProduct,
      wasteQtyByProduct: wasteQtyByProduct ?? this.wasteQtyByProduct,
      manualUnitPriceByProduct:
          manualUnitPriceByProduct ?? this.manualUnitPriceByProduct,
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
    );
    try {
      final draft = await ref.read(reconciliationServiceProvider).getDraft();
      final counted = <int, int>{};
      final sale = <int, int>{};
      final waste = <int, int>{};
      final prices = <int, String>{};
      for (final product in draft.products) {
        counted[product.productId] = product.expectedQty;
        sale[product.productId] = 0;
        waste[product.productId] = 0;
        prices[product.productId] = '';
      }

      state = state.copyWith(
        isLoading: false,
        draft: draft,
        countedQtyByProduct: counted,
        saleQtyByProduct: sale,
        wasteQtyByProduct: waste,
        manualUnitPriceByProduct: prices,
        clearPaymentMethod: true,
        wasteReason: '',
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
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
    );
  }

  void setSaleQty(int productId, int value) {
    final next = Map<int, int>.from(state.saleQtyByProduct);
    next[productId] = value;
    state = state.copyWith(
      saleQtyByProduct: next,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
    );
  }

  void setWasteQty(int productId, int value) {
    final next = Map<int, int>.from(state.wasteQtyByProduct);
    next[productId] = value;
    state = state.copyWith(
      wasteQtyByProduct: next,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
    );
  }

  void setManualUnitPrice(int productId, String value) {
    final next = Map<int, String>.from(state.manualUnitPriceByProduct);
    next[productId] = value;
    state = state.copyWith(
      manualUnitPriceByProduct: next,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
    );
  }

  void setPaymentMethod(String? method) {
    state = state.copyWith(
      paymentMethod: method,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
    );
  }

  void setWasteReason(String value) {
    state = state.copyWith(
      wasteReason: value,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
    );
  }

  Future<bool> submit() async {
    final draft = state.draft;
    final staffName = ref.read(loggedByProvider).trim();
    if (draft == null) {
      state = state.copyWith(errorMessage: 'Chưa có dữ liệu đối soát để gửi');
      return false;
    }

    final validationMessage = _validate(state, staffName);
    if (validationMessage != null) {
      state = state.copyWith(errorMessage: validationMessage);
      return false;
    }

    final lines = draft.products.map((product) {
      final manualValue =
          state.manualUnitPriceByProduct[product.productId] ?? '';
      final parsedPrice = double.tryParse(manualValue.trim());
      final saleQty = state.saleQtyByProduct[product.productId] ?? 0;
      return ReconciliationSubmitLine(
        productId: product.productId,
        expectedQty: product.expectedQty,
        countedQty: state.countedQtyByProduct[product.productId] ?? 0,
        saleQty: saleQty,
        wasteQty: state.wasteQtyByProduct[product.productId] ?? 0,
        manualUnitPrice: saleQty > 0 ? parsedPrice : null,
      );
    }).toList();

    state = state.copyWith(
      isSubmitting: true,
      clearErrorMessage: true,
      clearSubmitSuccessMessage: true,
    );

    try {
      final request = ReconciliationSubmitRequest(
        staffName: staffName,
        paymentMethod: state.hasSale ? state.paymentMethod : null,
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

  String? _validate(ReconciliationState currentState, String staffName) {
    if (staffName.isEmpty) {
      return 'Vui lòng chọn tên nhân viên trong Cài đặt trước khi đối soát';
    }
    final draft = currentState.draft;
    if (draft == null) {
      return 'Chưa có dữ liệu đối soát';
    }

    for (final product in draft.products) {
      final counted = currentState.countedQtyByProduct[product.productId] ?? 0;
      final sale = currentState.saleQtyByProduct[product.productId] ?? 0;
      final waste = currentState.wasteQtyByProduct[product.productId] ?? 0;
      if (counted < 0 || sale < 0 || waste < 0) {
        return 'Số lượng không được âm';
      }
      if (counted > product.expectedQty) {
        return 'Số đếm thực tế không được lớn hơn số tồn dự kiến';
      }

      final missing = product.expectedQty - counted;
      if (missing != sale + waste) {
        return 'Sản phẩm thiếu phải tách đúng: bán + hao hụt = số thiếu';
      }

      if (sale > 0) {
        final priceText =
            (currentState.manualUnitPriceByProduct[product.productId] ?? '')
                .trim();
        final parsedPrice = double.tryParse(priceText);
        if (parsedPrice == null || parsedPrice <= 0) {
          return 'Mỗi dòng bán phải có đơn giá nhập tay lớn hơn 0';
        }
      }
    }

    if (currentState.hasSale &&
        (currentState.paymentMethod != 'cash' &&
            currentState.paymentMethod != 'transfer')) {
      return 'Vui lòng chọn phương thức thanh toán';
    }

    if (currentState.hasWaste && currentState.wasteReason.trim().isEmpty) {
      return 'Vui lòng nhập lý do hao hụt';
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

final reconciliationProvider =
    NotifierProvider<ReconciliationNotifier, ReconciliationState>(
      ReconciliationNotifier.new,
    );
