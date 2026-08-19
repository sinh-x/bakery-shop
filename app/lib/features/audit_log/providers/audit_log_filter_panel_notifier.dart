import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Audit-log filter-panel state (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_entityType` selection field previously mutated via `setState`
/// inside `_AuditLogFilterPanelState`. The `TextEditingController`-backed
/// username / date-from / date-to fields stay on the widget
/// (`TextEditingController` lifecycle is acceptable-use per DG-404 guardrails).
/// The widget reads [auditLogFilterPanelProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class AuditLogFilterPanelState {
  const AuditLogFilterPanelState({
    this.entityType = '',
  });

  final String entityType;

  AuditLogFilterPanelState copyWith({String? entityType}) =>
      AuditLogFilterPanelState(entityType: entityType ?? this.entityType);
}

class AuditLogFilterPanelNotifier
    extends Notifier<AuditLogFilterPanelState> {
  @override
  AuditLogFilterPanelState build() => const AuditLogFilterPanelState();

  void setEntityType(String value) =>
      state = state.copyWith(entityType: value);

  void clear() => state = const AuditLogFilterPanelState();
}

final auditLogFilterPanelProvider =
    NotifierProvider<AuditLogFilterPanelNotifier, AuditLogFilterPanelState>(
        AuditLogFilterPanelNotifier.new);