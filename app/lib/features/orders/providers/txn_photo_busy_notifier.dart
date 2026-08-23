import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Transaction photo section busy-flag state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_photoBusy` field previously mutated via `setState` inside
/// `_TxnPhotoSectionState`. The widget reads [txnPhotoBusyProvider] and
/// invokes the notifier's [setBusy] method; no `setState` is required.
class TxnPhotoBusyNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) => state = false);
    return false;
  }

  void setBusy(bool value) => state = value;
}

final txnPhotoBusyProvider =
    NotifierProvider<TxnPhotoBusyNotifier, bool>(TxnPhotoBusyNotifier.new);
