import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';
import 'gated_page_physics.dart';
import 'order_creation_config.dart';
import 'order_stage_indicator.dart';

/// Shared wizard shell that renders stages 1-4 for both the normal order
/// creation flow and the POS checkout flow.
///
/// The orchestrator is the single source of truth for:
/// - the stage indicator row (reusing [OrderStageIndicator] with `posMode`)
/// - the per-stage widget construction (delegated to [OrderCreationConfig])
/// - forward/back stage navigation (FR8)
/// - the container that hosts the stage widgets (PageView / AnimatedSwitcher,
///   supplied via [StageContainerBuilder]) — FR1
///
/// It does NOT own submission logic (Phase 2), draft persistence (host screen
/// responsibility), or the POS payment step (stage 5 stays in the POS screen).
class OrderCreationOrchestrator extends ConsumerStatefulWidget {
  const OrderCreationOrchestrator({
    super.key,
    required this.config,
  });

  final OrderCreationConfig config;

  @override
  ConsumerState<OrderCreationOrchestrator> createState() =>
      _OrderCreationOrchestratorState();
}

class _OrderCreationOrchestratorState
    extends ConsumerState<OrderCreationOrchestrator> {
  OrderCreationConfig get _config => widget.config;

  NotifierProvider<OrderCreateStateNotifier, OrderCreateState>
      get _provider => _config.orderStateProvider;

  void _goToStage(int stage) {
    final clamped = stage.clamp(1, _config.stageCount);
    ref.read(_provider.notifier).goToStage(clamped);
    _config.onStageChange?.call(clamped);
  }

  void _onSwipe(DragEndDetails d) {
    if (!_config.enableSwipeNavigation) return;
    final s = ref.read(_provider);
    final pv = d.primaryVelocity;
    final target = targetStageForSwipe(
      velocity: Velocity(
        pixelsPerSecond: pv == null ? Offset.zero : Offset(pv, 0),
      ),
      currentStage: s.currentStage,
      pageCount: _config.stageCount,
    );
    if (target != null && s.canNavigateToStage(target)) _goToStage(target);
  }

  OrderCreationController get _controller =>
      OrderCreationController(goToStage: _goToStage);

  List<Widget> _buildStageWidgets() {
    final ctx = context;
    final c = _controller;
    return [
      _config.stage1Builder(ctx, c),
      _config.stage2Builder(ctx, c),
      _config.stage3Builder(ctx, c),
      _config.stage4Builder(ctx, c),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: OrderStageIndicator(
            currentStage: state.currentStage,
            posMode: _config.posMode,
            onStageTap: (s) {
              if (state.canNavigateToStage(s)) _goToStage(s);
            },
          ),
        ),
        Expanded(
          child: _config.enableSwipeNavigation
              ? GestureDetector(
                  onHorizontalDragEnd: _onSwipe,
                  child: _config.stageContainerBuilder(
                    context,
                    _buildStageWidgets(),
                    state.currentStage,
                  ),
                )
              : _config.stageContainerBuilder(
                  context,
                  _buildStageWidgets(),
                  state.currentStage,
                ),
        ),
      ],
    );
  }
}