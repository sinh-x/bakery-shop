import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// POS receipt screen state (DG-404 Phase 4.5 / FR2).
///
/// Owns the `_imageBytes`, `_error`, `_loading`, and `_printing` fields
/// previously mutated via `setState` inside `_PosReceiptScreenState`. The
/// widget reads [posReceiptProvider] and invokes the notifier's mutators;
/// no `setState` is required.
class PosReceiptState {
  const PosReceiptState({
    this.imageBytes,
    this.error,
    this.loading = true,
    this.printing = false,
  });

  final Uint8List? imageBytes;
  final String? error;
  final bool loading;
  final bool printing;

  PosReceiptState copyWith({
    Uint8List? imageBytes,
    String? error,
    bool? loading,
    bool? printing,
    bool clearError = false,
    bool clearImage = false,
  }) =>
      PosReceiptState(
        imageBytes: clearImage ? null : (imageBytes ?? this.imageBytes),
        error: clearError ? null : (error ?? this.error),
        loading: loading ?? this.loading,
        printing: printing ?? this.printing,
      );
}

/// `Notifier` that owns the POS receipt-screen state (DG-404 Phase 4.5 /
/// FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_PosReceiptScreenState` are now exposed as notifier methods. The widget
/// reads the state via [posReceiptProvider] and rebuilds on change — no
/// `setState` is required.
class PosReceiptNotifier extends Notifier<PosReceiptState> {
  int _printGeneration = 0;

  @override
  PosReceiptState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) {
        _printGeneration++;
        state = const PosReceiptState();
      },
    );
    return const PosReceiptState();
  }

  /// Record a successful receipt fetch.
  void setLoaded(Uint8List bytes) => state = state.copyWith(
        imageBytes: bytes,
        loading: false,
        clearError: true,
      );

  /// Record a failed receipt fetch.
  void setError(String message) => state = state.copyWith(
        error: message,
        loading: false,
      );

  /// Begin a print operation.
  int startPrinting() {
    state = state.copyWith(printing: true);
    return ++_printGeneration;
  }

  /// End a print operation.
  void stopPrinting() => state = state.copyWith(printing: false);

  void stopPrintingIfCurrent(int generation) {
    if (generation == _printGeneration) stopPrinting();
  }

  /// Reset back to the loading state (used by the retry button).
  void resetForRetry() => state = state.copyWith(
        loading: true,
        clearError: true,
      );
}

/// Provider for the POS receipt-screen state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final posReceiptProvider =
    NotifierProvider<PosReceiptNotifier, PosReceiptState>(PosReceiptNotifier.new);
