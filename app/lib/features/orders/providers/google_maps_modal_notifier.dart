import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Google Maps modal save-flag state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_saving` field previously mutated via `setState` inside
/// `_GoogleMapsModalState`. The widget reads [googleMapsModalProvider] and
/// invokes the notifier's [setSaving] method; no `setState` is required.
class GoogleMapsModalNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) => state = false);
    return false;
  }

  void setSaving(bool value) => state = value;
}

final googleMapsModalProvider = NotifierProvider<GoogleMapsModalNotifier, bool>(
  GoogleMapsModalNotifier.new,
);

/// Internal print dialog state (DG-404 Phase 4.6 / FR2). Owns the
/// `_printing` and `_statusText` fields previously mutated via `setState`
/// inside `_InternalPrintDialogState`. Reuses the
/// `OrderPrintChecklistState` shape from
/// `order_print_dialog_notifiers.dart` so both dialogs share a single
/// state class.
class InternalPrintNotifier extends Notifier<InternalPrintState> {
  InternalPrintNotifier(this.context);

  final FormDraftContext context;

  @override
  InternalPrintState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const InternalPrintState(),
    );
    return const InternalPrintState();
  }

  void startPrinting({String statusText = ''}) =>
      state = state.copyWith(printing: true, statusText: statusText);

  void setStatusText(String text) => state = state.copyWith(statusText: text);

  void finishPrinting() => state = state.copyWith(printing: false);
}

class InternalPrintState {
  const InternalPrintState({this.printing = false, this.statusText = ''});

  final bool printing;
  final String statusText;

  InternalPrintState copyWith({bool? printing, String? statusText}) =>
      InternalPrintState(
        printing: printing ?? this.printing,
        statusText: statusText ?? this.statusText,
      );
}

final internalPrintProvider =
    NotifierProvider.family<
      InternalPrintNotifier,
      InternalPrintState,
      FormDraftContext
    >(InternalPrintNotifier.new);
