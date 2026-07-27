import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/events_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/utils/api_error.dart' as api_error;
import '../api/reconciliation_service.dart';
import 'reconciliation_math.dart';
import 'reconciliation_state.dart';

class ReconciliationNotifier extends Notifier<ReconciliationState> {
  final Map<String, ReconciliationDraftOption> _draftOptionsByKey =
      <String, ReconciliationDraftOption>{};

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
      _draftOptionsByKey.clear();
      final counted = <String, int>{};
      final waste = <String, int>{};
      final wasteReasons = <String, String>{};
      final saleRows = <String, List<ReconciliationSaleRowInput>>{};
      for (final product in draft.products) {
        for (final option in product.options) {
          final key = reconciliationOptionKey(option.productId, option.normalizedPrice);
          _draftOptionsByKey[key] = option;
          counted[key] = option.expectedQty < 0 ? 0 : option.expectedQty;
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
      _draftOptionsByKey.clear();
      state = state.copyWith(
        isLoading: false,
        errorMessage: api_error.normalizeApiError(error).message,
      );
    } catch (_) {
      _draftOptionsByKey.clear();
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải dữ liệu đối soát',
      );
    }
  }

  void setCountedQty(Object optionKeyOrProductId, int value) {
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
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
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
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

  void addSaleRow(Object optionKeyOrProductId, {int? defaultUnitPrice}) {
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
    final next = Map<String, List<ReconciliationSaleRowInput>>.from(
      state.saleRowsByOption,
    );
    final rows = List<ReconciliationSaleRowInput>.from(next[optionKey] ?? []);
    rows.add(ReconciliationSaleRowInput(unitPrice: defaultUnitPrice?.toDouble()));
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
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
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
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
    _updateSaleRow(optionKey, rowIndex, (row) => row.copyWith(quantity: value));
  }

  void setSaleRowUnitPrice(
    Object optionKeyOrProductId,
    int rowIndex,
    double? value,
  ) {
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
    _updateSaleRow(
      optionKey,
      rowIndex,
      (row) => row.copyWith(unitPrice: value, clearUnitPrice: value == null),
    );
  }

  void setSaleRowPaymentMethod(
    Object optionKeyOrProductId,
    int rowIndex,
    String? method,
  ) {
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
    _updateSaleRow(
      optionKey,
      rowIndex,
      (row) => row.copyWith(
        paymentMethod: method,
        clearPaymentMethod: method == null,
      ),
    );
  }

  void fillSaleRowPriceFromChip(
    Object optionKeyOrProductId,
    int rowIndex,
    double unitPrice,
  ) {
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
    setSaleRowUnitPrice(optionKey, rowIndex, unitPrice);
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
    final optionKey = normalizeReconciliationOptionKey(optionKeyOrProductId, state);
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

    final validation = validateReconciliationState(state, staffName);
    if (validation != null) {
      state = state.copyWith(
        errorMessage: validation.message,
        optionErrors: validation.optionErrors,
        saleRowErrorsByOption: validation.saleRowErrorsByOption,
      );
      return false;
    }

    final lines = buildSubmitLines(state);

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

      final result = await ref.read(reconciliationServiceProvider).submit(request);
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
        errorMessage: api_error.normalizeApiError(error).message,
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

  bool prepareSubmitReview() {
    final staffName = ref.read(loggedByProvider).trim();
    final validation = validateReconciliationState(state, staffName);
    if (validation == null) {
      state = state.copyWith(
        clearErrorMessage: true,
        optionErrors: <String, String>{},
        saleRowErrorsByOption: <String, List<ReconciliationSaleRowError>>{},
      );
      return true;
    }

    state = state.copyWith(
      errorMessage: validation.message,
      optionErrors: validation.optionErrors,
      saleRowErrorsByOption: validation.saleRowErrorsByOption,
    );
    return false;
  }
}
