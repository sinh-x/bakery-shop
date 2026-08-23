import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../orders/providers/order_draft_contexts.dart';

/// POS checkout screen state (DG-404 Phase 4.5 / FR2).
///
/// Owns the `_navigatingAfterCheckout`, `_posDeliverImmediately`,
/// `_stage3ShowFullOptions`, and `_isFastPath` fields previously mutated
/// via `setState` (and direct field writes that triggered empty
/// `setState(() {})` rebuilds) inside `_PosCheckoutScreenState`. The widget
/// reads [posCheckoutProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class PosCheckoutState {
  const PosCheckoutState({
    this.navigatingAfterCheckout = false,
    this.posDeliverImmediately = false,
    this.stage3ShowFullOptions = false,
    this.isFastPath = false,
  });

  final bool navigatingAfterCheckout;
  final bool posDeliverImmediately;
  final bool stage3ShowFullOptions;
  final bool isFastPath;

  PosCheckoutState copyWith({
    bool? navigatingAfterCheckout,
    bool? posDeliverImmediately,
    bool? stage3ShowFullOptions,
    bool? isFastPath,
  }) => PosCheckoutState(
    navigatingAfterCheckout:
        navigatingAfterCheckout ?? this.navigatingAfterCheckout,
    posDeliverImmediately: posDeliverImmediately ?? this.posDeliverImmediately,
    stage3ShowFullOptions: stage3ShowFullOptions ?? this.stage3ShowFullOptions,
    isFastPath: isFastPath ?? this.isFastPath,
  );
}

/// `Notifier` that owns the POS checkout-screen state (DG-404 Phase 4.5 /
/// FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_PosCheckoutScreenState` are now exposed as notifier methods. The
/// widget reads the state via [posCheckoutProvider] and rebuilds on change
/// — no `setState` is required.
class PosCheckoutNotifier extends Notifier<PosCheckoutState> {
  @override
  PosCheckoutState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const PosCheckoutState(),
    );
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<PosCheckoutState>(
              OrderDraftContexts.posCheckoutOptions,
            ) ??
        const PosCheckoutState();
  }

  void _setDraft(PosCheckoutState next) {
    state = next;
    ref
        .read(formDraftSessionProvider.notifier)
        .retainDraft(
          OrderDraftContexts.posCheckoutOptions,
          next.copyWith(navigatingAfterCheckout: false),
        );
  }

  /// Seed the initial fast-path flag from the screen's `fastPath` ctor
  /// argument. Called once from the screen's `initState` before any
  /// mutation.
  void seedFastPath(bool fastPath) =>
      state = state.copyWith(isFastPath: fastPath);

  /// Mark the screen as navigating after a successful checkout (suppresses
  /// the empty-cart guard).
  void markNavigatingAfterCheckout() =>
      state = state.copyWith(navigatingAfterCheckout: true);

  /// Reset the navigating-after-checkout latch so a fresh checkout session
  /// re-enables the empty-cart guard. Without this, the global
  /// non-autoDispose `NotifierProvider` would stay `true` after the first
  /// checkout and the empty-cart guard would no longer redirect to `/pos`
  /// (DG-404 review CQ-2). Invoked when entering a fresh checkout session
  /// (in `_initPosState` alongside `seedFastPath`).
  void resetNavigatingAfterCheckout() =>
      state = state.copyWith(navigatingAfterCheckout: false);

  /// Refresh route-instance metadata without clearing unfinished checkout
  /// choices such as the Stage 3 delivery flags.
  void startSession({required bool fastPath}) {
    final retained = ref
        .read(formDraftSessionProvider.notifier)
        .readDraft<PosCheckoutState>(OrderDraftContexts.posCheckoutOptions);
    state = (retained ?? const PosCheckoutState()).copyWith(
      navigatingAfterCheckout: false,
      isFastPath: fastPath,
    );
  }

  void clearAfterSubmit() {
    ref
        .read(formDraftSessionProvider.notifier)
        .clearDraft(OrderDraftContexts.posCheckoutOptions);
    state = const PosCheckoutState(navigatingAfterCheckout: true);
  }

  /// Set the deliverImmediately flag (used by the Giao ngay fast-path and
  /// the Stage 3 pickup screen).
  void setDeliverImmediately(bool value) =>
      _setDraft(state.copyWith(posDeliverImmediately: value));

  /// Show the full Stage 3 delivery options (after "Giao sau" on the pickup
  /// screen).
  void setStage3ShowFullOptions(bool value) =>
      _setDraft(state.copyWith(stage3ShowFullOptions: value));

  /// Reset the Stage 3 flags when entering Stage 3 (clears
  /// deliverImmediately and stage3ShowFullOptions).
  void resetStage3() => _setDraft(
    state.copyWith(posDeliverImmediately: false, stage3ShowFullOptions: false),
  );
}

/// Provider for the POS checkout-screen state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final posCheckoutProvider =
    NotifierProvider<PosCheckoutNotifier, PosCheckoutState>(
      PosCheckoutNotifier.new,
    );

/// Rebuild trigger for the POS checkout screen's stage container
/// (DG-404 Phase 4.5).
///
/// `PosCheckoutPaymentController` owns plain (non-provider) fields like
/// `selectedPaymentMethod`, `paidAmount`, `isProcessing`, etc. The
/// `stageContainerBuilder` re-reads these fields on every rebuild. Before
/// migration the screen used `setState(() {})` (via the
/// `PosPaymentStepBuilder.onChanged` callback) to trigger a rebuild so the
/// stage container re-read the controller fields. This notifier replaces
/// those empty `setState` calls with a counter bump that the stage
/// container watches; the controller fields are re-read on every rebuild.
/// No business-logic state lives here — it is a pure rebuild signal.
class PosCheckoutRebuildNotifier extends Notifier<int> {
  @override
  int build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) => state = 0);
    return 0;
  }

  /// Bump the counter to trigger a rebuild of widgets watching this
  /// provider.
  void bump() => state++;
}

/// Provider used as a rebuild signal for the POS checkout stage container.
final posCheckoutRebuildProvider =
    NotifierProvider<PosCheckoutRebuildNotifier, int>(
      PosCheckoutRebuildNotifier.new,
    );
