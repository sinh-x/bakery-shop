import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';
import 'order_creation_config.dart';

/// Minimal host surface that [OrderSubmissionMixin] depends on so the mixin
/// is reusable outside [OrderCreationOrchestratorState] and does not create a
/// circular import with the orchestrator file (CQ-2 / CQ-3).
///
/// The orchestrator state implements this interface; the mixin is constrained
/// to it via `on OrderSubmissionHost, ConsumerState`. Any state class that
/// exposes [config] and [provider] can host the submission spine — the rest of
/// the host surface (`ref`, `mounted`, `setState`, `context`) comes from
/// [ConsumerState].
abstract class OrderSubmissionHost {
  /// The workflow configuration (stage builders, hooks, providers).
  OrderCreationConfig get config;

  /// The provider backing the wizard state.
  NotifierProvider<OrderCreateStateNotifier, OrderCreateState> get provider;
}