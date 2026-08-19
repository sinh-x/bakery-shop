import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cake-detail blank section busy-flag state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_busy` field previously mutated via `setState` inside
/// `_CakeDetailBlankSectionState`. The widget reads
/// [cakeDetailBlankBusyProvider] and invokes the notifier's [setBusy]
/// method; no `setState` is required.
class CakeDetailBlankBusyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setBusy(bool value) => state = value;
}

final cakeDetailBlankBusyProvider =
    NotifierProvider<CakeDetailBlankBusyNotifier, bool>(
        CakeDetailBlankBusyNotifier.new);