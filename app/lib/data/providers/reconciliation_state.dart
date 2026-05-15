import '../api/reconciliation_service.dart';

class ReconciliationSaleRowInput {
  ReconciliationSaleRowInput({
    this.quantity = 0,
    this.unitPrice,
    this.paymentMethod,
  });

  final int quantity;
  final double? unitPrice;
  final String? paymentMethod;

  ReconciliationSaleRowInput copyWith({
    int? quantity,
    double? unitPrice,
    String? paymentMethod,
    bool clearUnitPrice = false,
    bool clearPaymentMethod = false,
  }) {
    return ReconciliationSaleRowInput(
      quantity: quantity ?? this.quantity,
      unitPrice: clearUnitPrice ? null : (unitPrice ?? this.unitPrice),
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
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
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

String reconciliationOptionKey(int productId, int normalizedPrice) {
  return '$productId:$normalizedPrice';
}

String normalizeReconciliationOptionKey(
  Object optionKeyOrProductId,
  ReconciliationState currentState,
) {
  if (optionKeyOrProductId is String) {
    return optionKeyOrProductId;
  }
  if (optionKeyOrProductId is int) {
    final prefix = '$optionKeyOrProductId:';
    final allKeys = <String>{
      ...currentState.countedQtyByOption.keys,
      ...currentState.wasteQtyByOption.keys,
      ...currentState.wasteReasonByOption.keys,
      ...currentState.saleRowsByOption.keys,
    };
    final matched = allKeys.where((key) => key.startsWith(prefix)).toList();
    if (matched.length == 1) {
      return matched.first;
    }
    return reconciliationOptionKey(optionKeyOrProductId, 0);
  }
  throw ArgumentError('Invalid option key: $optionKeyOrProductId');
}
