import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Delivery tab content state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_showToday`, `_viewMode`, and `_selectedStaffId` fields
/// previously mutated via `setState` inside `_DeliveryContentState`. The
/// widget reads [deliveryContentProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class DeliveryContentState {
  const DeliveryContentState({
    this.showToday = true,
    this.viewMode = 'day',
    this.selectedStaffId,
  });

  final bool showToday;
  final String viewMode;
  final String? selectedStaffId;

  DeliveryContentState copyWith({
    bool? showToday,
    String? viewMode,
    String? selectedStaffId,
    bool clearSelectedStaffId = false,
  }) =>
      DeliveryContentState(
        showToday: showToday ?? this.showToday,
        viewMode: viewMode ?? this.viewMode,
        selectedStaffId: clearSelectedStaffId
            ? null
            : (selectedStaffId ?? this.selectedStaffId),
      );
}

class DeliveryContentNotifier extends Notifier<DeliveryContentState> {
  @override
  DeliveryContentState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const DeliveryContentState(),
    );
    return const DeliveryContentState();
  }

  void setShowToday(bool value) => state = state.copyWith(showToday: value);

  void setViewMode(String mode) => state = state.copyWith(viewMode: mode);

  void setSelectedStaffId(String? id) {
    if (id == null) {
      state = state.copyWith(clearSelectedStaffId: true);
    } else {
      state = state.copyWith(selectedStaffId: id);
    }
  }

  /// Reset the staff filter to "All" (null) when the user navigates away
  /// from the delivery tab (AC7).
  void resetStaffFilter() =>
      state = state.copyWith(clearSelectedStaffId: true);
}

final deliveryContentProvider =
    NotifierProvider<DeliveryContentNotifier, DeliveryContentState>(
        DeliveryContentNotifier.new);
