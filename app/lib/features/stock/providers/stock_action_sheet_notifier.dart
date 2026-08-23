import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

const _unset = Object();

/// Form state for the stock-action bottom sheet (DG-404 Phase 4.7 /
/// FR2).
///
/// Holds the `_isLoading` flag and `_selectedNormalizedPrice` value
/// previously mutated via `setState` inside `_StockActionSheetState`.
/// The quantity / reason / note `TextEditingController`s stay on the
/// widget because `TextEditingController` lifecycle is an
/// acceptable-use case (see DG-404 guardrails). The widget reads
/// [stockActionSheetProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class StockActionSheetState {
  const StockActionSheetState({
    this.isLoading = false,
    this.selectedNormalizedPrice,
    this.initialNormalizedPrice,
    this.quantity = '',
    this.reason = '',
    this.note = '',
    this.initialized = false,
  });

  final bool isLoading;
  final int? selectedNormalizedPrice;
  final int? initialNormalizedPrice;
  final String quantity;
  final String reason;
  final String note;
  final bool initialized;

  StockActionSheetState copyWith({
    bool? isLoading,
    Object? selectedNormalizedPrice = _unset,
    Object? initialNormalizedPrice = _unset,
    String? quantity,
    String? reason,
    String? note,
    bool? initialized,
  }) {
    return StockActionSheetState(
      isLoading: isLoading ?? this.isLoading,
      selectedNormalizedPrice: identical(selectedNormalizedPrice, _unset)
          ? this.selectedNormalizedPrice
          : selectedNormalizedPrice as int?,
      initialNormalizedPrice: identical(initialNormalizedPrice, _unset)
          ? this.initialNormalizedPrice
          : initialNormalizedPrice as int?,
      quantity: quantity ?? this.quantity,
      reason: reason ?? this.reason,
      note: note ?? this.note,
      initialized: initialized ?? this.initialized,
    );
  }
}

/// `Notifier` that owns the stock-action-sheet state (DG-404 Phase 4.7
/// / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_StockActionSheetState` are now exposed as notifier methods. The
/// widget reads the state via [stockActionSheetProvider] and rebuilds
/// on change — no `setState` is required.
class StockActionSheetNotifier extends Notifier<StockActionSheetState> {
  StockActionSheetNotifier(this.context);

  final FormDraftContext context;
  bool _clearingRegistry = false;

  @override
  StockActionSheetState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      state = const StockActionSheetState();
    });
    ref.listen(formDraftSessionProvider, (previous, next) {
      if (!_clearingRegistry &&
          previous?.containsKey(context) == true &&
          !next.containsKey(context)) {
        state = const StockActionSheetState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<StockActionSheetState>(context) ??
        const StockActionSheetState();
  }

  /// Seed the initial normalized price selection from the item's
  /// per-chip list and the optional pre-selected price. Called once
  /// from `initState`.
  void initialize(int? price) {
    if (state.initialized) return;
    state = state.copyWith(
      selectedNormalizedPrice: price,
      initialNormalizedPrice: price,
      initialized: true,
    );
  }

  void setSelectedNormalizedPrice(int? value) {
    state = state.copyWith(selectedNormalizedPrice: value);
    _retain();
  }

  void setQuantity(String value) {
    state = state.copyWith(quantity: value);
    _retain();
  }

  void setReason(String value) {
    state = state.copyWith(reason: value);
    _retain();
  }

  void setNote(String value) {
    state = state.copyWith(note: value);
    _retain();
  }

  void setLoading(bool value) => state = state.copyWith(isLoading: value);

  Object? get retainedDraft => ref.read(formDraftSessionProvider)[context];

  bool completeSuccess(Object? submittedDraft) {
    final drafts = ref.read(formDraftSessionProvider.notifier);
    final currentDraft = ref.read(formDraftSessionProvider)[context];
    final canClear = submittedDraft == null
        ? currentDraft == null
        : drafts.clearDraftIfUnchanged(context, submittedDraft);
    if (canClear) {
      state = const StockActionSheetState();
    } else {
      state = state.copyWith(isLoading: false);
    }
    return canClear;
  }

  void clear() {
    state = const StockActionSheetState();
    _clearRegistry();
  }

  void discard(int? initialPrice) {
    state = StockActionSheetState(
      selectedNormalizedPrice: initialPrice,
      initialNormalizedPrice: initialPrice,
      initialized: true,
    );
    _clearRegistry();
  }

  void _retain() {
    if (!state.isDirty) {
      _clearRegistry();
      return;
    }
    ref
        .read(formDraftSessionProvider.notifier)
        .retainDraft(context, state.copyWith(isLoading: false));
  }

  void _clearRegistry() {
    _clearingRegistry = true;
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    _clearingRegistry = false;
  }
}

extension on StockActionSheetState {
  bool get isDirty =>
      quantity.isNotEmpty ||
      reason.isNotEmpty ||
      note.isNotEmpty ||
      selectedNormalizedPrice != initialNormalizedPrice;
}

FormDraftContext stockActionDraftContext({
  required int productId,
  required String action,
  required int? normalizedPrice,
}) => FormDraftContext(
  formType: 'stock-action:$action',
  mode: FormDraftMode.action,
  productId: '$productId',
  variantId: normalizedPrice?.toString(),
);

/// Provider for the stock-action-sheet state. The sheet reads this and
/// calls the notifier's mutators; no `setState` is required.
final stockActionSheetProvider =
    NotifierProvider.family<
      StockActionSheetNotifier,
      StockActionSheetState,
      FormDraftContext
    >(StockActionSheetNotifier.new);
