import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';

/// Builds the container that hosts the wizard stage widgets.
///
/// Each workflow provides its own implementation:
/// - Normal order → `PageView` driven by a `PageController` synced to
///   `currentStage`.
/// - POS → `AnimatedSwitcher` keyed on `currentStage`.
///
/// The orchestrator owns the 4 stage widgets and the current stage number;
/// the container decides how to present/animate them.
typedef StageContainerBuilder = Widget Function(
  BuildContext context,
  List<Widget> stageWidgets,
  int currentStage,
);

/// Builds a single wizard stage widget. The [controller] exposes the
/// orchestrator's stage-navigation primitive so the stage's
/// `onContinue`/`onBack` callbacks can delegate back to the orchestrator
/// without knowing which provider instance or container is in use.
typedef StageBuilder = Widget Function(
  BuildContext context,
  OrderCreationController controller,
);

/// Surface handed to each stage builder so stages can drive wizard navigation
/// without coupling to the host screen.
class OrderCreationController {
  /// Moves the wizard to the 1-based [stage] (1..4). The orchestrator updates
  /// the configured [OrderCreateStateNotifier] and notifies the container.
  final void Function(int stage) goToStage;

  const OrderCreationController({required this.goToStage});
}

/// Workflow-specific configuration consumed by [OrderCreationOrchestrator].
///
/// This model is the single change point for behaviour that differs between
/// the normal order creation flow and the POS checkout flow while sharing the
/// 4-stage wizard shell. Phase 1 covers stage rendering (FR1, FR8); submission
/// hooks are added in Phase 2.
@immutable
class OrderCreationConfig {
  /// Provider instance backing this wizard — `orderCreateStateProvider` for
  /// normal orders, `posOrderStateProvider` for POS.
  final NotifierProvider<OrderCreateStateNotifier, OrderCreateState>
      orderStateProvider;

  /// Whether the stage indicator renders the 5-stage POS variant. Only the
  /// first 4 stages are rendered by the orchestrator; stage 5 stays in the
  /// POS screen wrapper.
  final bool posMode;

  /// Gates draft save/restore. `true` for normal order, `false` for POS
  /// (FR6). Used by the host screen in later phases; stored here so the
  /// orchestrator is the single source of truth for workflow flags.
  final bool enableDraft;

  /// Enables horizontal-swipe stage navigation (normal order only). POS uses
  /// explicit back/continue buttons, so swipe is disabled there.
  final bool enableSwipeNavigation;

  /// Number of wizard stages rendered by the orchestrator. Both workflows
  /// currently render 4 stages; kept configurable for future extensibility.
  final int stageCount;

  /// Per-stage widget builders. Each workflow supplies its own builders so
  /// POS can substitute `PosReviewPanel` for stage 4 and the pickup variant
  /// for stage 3 while reusing the shared shell.
  final StageBuilder stage1Builder;
  final StageBuilder stage2Builder;
  final StageBuilder stage3Builder;
  final StageBuilder stage4Builder;

  /// Container builder that wraps the stage widgets (PageView / AnimatedSwitcher).
  final StageContainerBuilder stageContainerBuilder;

  /// Optional hook invoked after the orchestrator advances to a new stage.
  /// Used by workflows that need to react to stage changes (e.g. resetting
  /// POS pickup flags when entering stage 3).
  final void Function(int stage)? onStageChange;

  const OrderCreationConfig({
    required this.orderStateProvider,
    required this.posMode,
    required this.enableDraft,
    required this.enableSwipeNavigation,
    required this.stage1Builder,
    required this.stage2Builder,
    required this.stage3Builder,
    required this.stage4Builder,
    required this.stageContainerBuilder,
    this.stageCount = 4,
    this.onStageChange,
  });
}