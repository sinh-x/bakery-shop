import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Audit-log tile expansion state (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_expanded` toggle previously mutated via `setState` inside
/// `_AuditLogTileState`. Keyed by the entry id via a family provider so each
/// tile in the list maintains its own expansion state. Following the
/// codebase convention for `NotifierProvider.family` (arg as constructor
/// param, see `ExpenseHistoryPhotoNotifier`).
class AuditLogTileState {
  const AuditLogTileState({this.expanded = false});

  final bool expanded;

  AuditLogTileState copyWith({bool? expanded}) =>
      AuditLogTileState(expanded: expanded ?? this.expanded);
}

class AuditLogTileNotifier extends Notifier<AuditLogTileState> {
  final int entryId;

  AuditLogTileNotifier(this.entryId);

  @override
  AuditLogTileState build() => const AuditLogTileState();

  void toggle() => state = state.copyWith(expanded: !state.expanded);
}

/// Family provider for the audit-log tile expansion state, keyed by entry id.
final auditLogTileProvider =
    NotifierProvider.family<AuditLogTileNotifier, AuditLogTileState, int>(
        AuditLogTileNotifier.new);