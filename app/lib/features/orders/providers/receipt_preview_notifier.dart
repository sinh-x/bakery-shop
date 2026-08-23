import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Receipt-preview screen state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_imageBytes`, `_error`, `_loading`, and `_printing` fields
/// previously mutated via `setState` inside `_ReceiptPreviewScreenState`.
/// The widget reads [receiptPreviewProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class ReceiptPreviewState {
  const ReceiptPreviewState({
    this.imageBytes,
    this.error,
    this.loading = true,
    this.printing = false,
  });

  final Uint8List? imageBytes;
  final String? error;
  final bool loading;
  final bool printing;

  ReceiptPreviewState copyWith({
    Uint8List? imageBytes,
    String? error,
    bool? loading,
    bool? printing,
    bool clearError = false,
    bool clearImageBytes = false,
  }) =>
      ReceiptPreviewState(
        imageBytes: clearImageBytes ? null : (imageBytes ?? this.imageBytes),
        error: clearError ? null : (error ?? this.error),
        loading: loading ?? this.loading,
        printing: printing ?? this.printing,
      );
}

class ReceiptPreviewNotifier extends Notifier<ReceiptPreviewState> {
  @override
  ReceiptPreviewState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const ReceiptPreviewState(),
    );
    return const ReceiptPreviewState();
  }

  void setImage(Uint8List bytes) => state = state.copyWith(
        imageBytes: bytes,
        loading: false,
        clearError: true,
      );

  void setError(String error) => state = state.copyWith(
        error: error,
        loading: false,
      );

  void retry() => state = state.copyWith(
        loading: true,
        clearError: true,
      );

  void setPrinting(bool value) => state = state.copyWith(printing: value);
}

final receiptPreviewProvider =
    NotifierProvider<ReceiptPreviewNotifier, ReceiptPreviewState>(
        ReceiptPreviewNotifier.new);
