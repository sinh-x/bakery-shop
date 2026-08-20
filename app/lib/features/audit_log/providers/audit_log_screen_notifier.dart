import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Audit-log screen state (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_filtersVisible` toggle previously mutated via `setState`
/// inside `_AuditLogScreenState`. The widget reads
/// [auditLogScreenProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class AuditLogScreenState {
  const AuditLogScreenState({this.filtersVisible = true});

  final bool filtersVisible;

  AuditLogScreenState copyWith({bool? filtersVisible}) =>
      AuditLogScreenState(filtersVisible: filtersVisible ?? this.filtersVisible);
}

class AuditLogScreenNotifier extends Notifier<AuditLogScreenState> {
  @override
  AuditLogScreenState build() => const AuditLogScreenState();

  void toggleFiltersVisible() =>
      state = state.copyWith(filtersVisible: !state.filtersVisible);
}

final auditLogScreenProvider =
    NotifierProvider<AuditLogScreenNotifier, AuditLogScreenState>(
        AuditLogScreenNotifier.new);