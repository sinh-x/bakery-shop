import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/printer_service.dart';
import 'form_draft_session_notifier.dart';

/// Collision-safe identity for one mounted printer-picker operation.
///
/// Equality intentionally uses object identity. The matching provider family is
/// auto-disposed when its dialog stops listening, so completed dialog tokens do
/// not accumulate for the application session.
class PrinterPickerDialogContext {}

/// Phases of the printer picker flow (DG-404 Phase 4.7 / FR2).
/// Public equivalent of the pre-migration private `_PickerState` enum
/// in `printer_picker_dialog.dart`.
enum PrinterPickerPhase {
  loading,
  deviceList,
  noDevices,
  connecting,
  printing,
  error,
}

/// Sync state for the printer picker bottom sheet (DG-404 Phase 4.7
/// / FR2). Owns the picker phase, discovered devices list, error
/// message, and the in-progress connection target name — previously
/// held as `setState` fields inside
/// `_PrinterPickerBottomSheetState`.
class PrinterPickerDialogState {
  const PrinterPickerDialogState({
    this.phase = PrinterPickerPhase.loading,
    this.devices = const <DiscoveredPrinter>[],
    this.errorMessage,
    this.connectingToName,
  });

  final PrinterPickerPhase phase;
  final List<DiscoveredPrinter> devices;
  final String? errorMessage;
  final String? connectingToName;

  PrinterPickerDialogState copyWith({
    PrinterPickerPhase? phase,
    List<DiscoveredPrinter>? devices,
    String? errorMessage,
    String? connectingToName,
    bool clearErrorMessage = false,
    bool clearConnectingToName = false,
  }) {
    return PrinterPickerDialogState(
      phase: phase ?? this.phase,
      devices: devices ?? this.devices,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      connectingToName: clearConnectingToName
          ? null
          : (connectingToName ?? this.connectingToName),
    );
  }
}

/// `Notifier` that owns the printer picker bottom-sheet state
/// (DG-404 Phase 4.7 / FR2). Sync state because all mutations are
/// local; the actual Bluetooth scan / connect / print flow is driven
/// by the widget, which reports outcomes back to this notifier.
class PrinterPickerNotifier extends Notifier<PrinterPickerDialogState> {
  PrinterPickerNotifier(this.context);

  final PrinterPickerDialogContext context;

  @override
  PrinterPickerDialogState build() {
    ref.watch(formDraftSessionEpochProvider);
    return const PrinterPickerDialogState();
  }

  void startLoading() => state = const PrinterPickerDialogState();

  void setError(String message) => state = state.copyWith(
    phase: PrinterPickerPhase.error,
    errorMessage: message,
  );

  void setDevices(List<DiscoveredPrinter> devices) => state = state.copyWith(
    phase: devices.isEmpty
        ? PrinterPickerPhase.noDevices
        : PrinterPickerPhase.deviceList,
    devices: devices,
  );

  void startConnecting(String deviceName) => state = state.copyWith(
    phase: PrinterPickerPhase.connecting,
    connectingToName: deviceName,
  );

  void setPrinting() =>
      state = state.copyWith(phase: PrinterPickerPhase.printing);
}

/// Provider for the printer picker bottom-sheet state.
final printerPickerProvider = NotifierProvider.autoDispose
    .family<
      PrinterPickerNotifier,
      PrinterPickerDialogState,
      PrinterPickerDialogContext
    >(PrinterPickerNotifier.new);
