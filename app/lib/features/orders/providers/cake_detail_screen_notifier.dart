import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Cake-detail screen transition/save-flag state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_transitioning` and `_saving` fields previously mutated via
/// `setState` inside `_CakeDetailScreenState`. The widget reads
/// [cakeDetailScreenProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class CakeDetailScreenState {
  const CakeDetailScreenState({
    this.transitioning = false,
    this.saving = false,
  });

  final bool transitioning;
  final bool saving;

  CakeDetailScreenState copyWith({
    bool? transitioning,
    bool? saving,
  }) =>
      CakeDetailScreenState(
        transitioning: transitioning ?? this.transitioning,
        saving: saving ?? this.saving,
      );
}

class CakeDetailScreenNotifier extends Notifier<CakeDetailScreenState> {
  @override
  CakeDetailScreenState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const CakeDetailScreenState(),
    );
    return const CakeDetailScreenState();
  }

  void setTransitioning(bool value) =>
      state = state.copyWith(transitioning: value);

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

final cakeDetailScreenProvider =
    NotifierProvider<CakeDetailScreenNotifier, CakeDetailScreenState>(
        CakeDetailScreenNotifier.new);

/// Order-detail screen transition-flag state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_transitioning` field previously mutated via `setState` inside
/// `_OrderDetailScreenState`. The widget reads [orderDetailScreenProvider]
/// and invokes the notifier's [setTransitioning] method; no `setState` is
/// required.
class OrderDetailScreenNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) => state = false);
    return false;
  }

  void setTransitioning(bool value) => state = value;
}

final orderDetailScreenProvider =
    NotifierProvider<OrderDetailScreenNotifier, bool>(
        OrderDetailScreenNotifier.new);
