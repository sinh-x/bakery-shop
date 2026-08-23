import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Order info block staff-assignment state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_selectedStaffId` and `_savingAssignment` fields previously
/// mutated via `setState` inside `_OrderInfoBlockState`. The widget reads
/// [orderInfoBlockProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class OrderInfoBlockState {
  const OrderInfoBlockState({
    this.selectedStaffId,
    this.savingAssignment = false,
  });

  final String? selectedStaffId;
  final bool savingAssignment;

  OrderInfoBlockState copyWith({
    String? selectedStaffId,
    bool? savingAssignment,
  }) =>
      OrderInfoBlockState(
        selectedStaffId: selectedStaffId ?? this.selectedStaffId,
        savingAssignment: savingAssignment ?? this.savingAssignment,
      );
}

class OrderInfoBlockNotifier extends Notifier<OrderInfoBlockState> {
  @override
  OrderInfoBlockState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const OrderInfoBlockState(),
    );
    return const OrderInfoBlockState();
  }

  /// Sync the local selection from the authoritative order prop on rebuild
  /// (e.g. after a successful PATCH refresh or external claim/unclaim).
  void syncFromOrder(String? assignedStaffId) {
    if (state.selectedStaffId != assignedStaffId && !state.savingAssignment) {
      state = state.copyWith(selectedStaffId: assignedStaffId);
    }
  }

  /// Mark a new staff selection and start the save round-trip.
  void startSave(String? staffId) =>
      state = state.copyWith(selectedStaffId: staffId, savingAssignment: true);

  /// Revert the local selection back to the authoritative order value on
  /// failure.
  void revert(String? assignedStaffId) => state = OrderInfoBlockState(
        selectedStaffId: assignedStaffId,
        savingAssignment: false,
      );

  /// Clear the saving flag after the round-trip completes.
  void finishSave() => state = state.copyWith(savingAssignment: false);
}

final orderInfoBlockProvider =
    NotifierProvider<OrderInfoBlockNotifier, OrderInfoBlockState>(
        OrderInfoBlockNotifier.new);
