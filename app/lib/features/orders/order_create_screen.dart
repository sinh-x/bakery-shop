import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/customer_service.dart';
import '../../shared/providers/logged_by_provider.dart';
import '../../providers/order/order_create_state_provider.dart';
import '../../providers/order/order_draft_provider.dart';
import '../../shared/labels/templates.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../templates/widgets/template_picker_modal.dart';
import 'template_context_builder.dart';
import 'widgets/order_creation_config.dart';
import 'widgets/order_creation_orchestrator.dart';
import 'widgets/stage1_product_selection_screen.dart';
import 'widgets/stage2_customer_info_screen.dart';
import 'widgets/stage3_delivery_options_screen.dart';
import 'widgets/stage4_review_screen.dart';
import 'package:bakery_app/shared/labels/orders.dart';
/// Normal order creation wizard.
///
/// Thin wrapper over [OrderCreationOrchestrator] (Phase 3 of DG-322). The
/// orchestrator owns the stage shell, draft save/restore (FR6), swipe
/// navigation, and the shared submission spine. This screen supplies the
/// normal-order [OrderCreationConfig]:
/// - PageView container (preserves swipe + animated stage transitions).
/// - `enableDraft: true` / `enableCartSync: false` (FR6/FR7).
/// - `onBeforeSubmit`: auto-create a customer when name+phone are present.
/// - `onAfterSubmit`: clear draft, reset state, show success snackbar.
/// - `onNavigateAfterSubmit`: `pushReplacement('/orders/{orderRef}')` — the
///   FR2 fix so back from detail returns to the order list, not the empty
///   creation screen.
/// - `createdByResolver`: reads `loggedByProvider` (preserves pre-refactor
///   `createdBy: staffName` behaviour).
class OrderCreateScreen extends ConsumerStatefulWidget {
  const OrderCreateScreen({super.key});

  @override
  ConsumerState<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends ConsumerState<OrderCreateScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    // Sync the PageController's initial page with the draft-restored stage so
    // the PageView opens on the right stage when a draft is hydrated by the
    // orchestrator. The orchestrator owns the full restore; this only reads
    // the persisted stage for initial-page placement.
    final draft = ref.read(orderDraftProvider);
    final initialStage = draft != null ? draft.currentStage.clamp(1, 4) : 1;
    _pageController = PageController(initialPage: initialStage - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// DG-375 Phase 4.3 / FR2 / AC2: opens the template picker modal filled
  /// from the current create-wizard state. Used by the overflow menu and the
  /// review-stage button.
  void _openTemplatePicker() {
    final state = ref.read(orderCreateStateProvider);
    final ctx = buildTemplateContextFromCreateWizard(
      items: state.items,
      wizardData: state.wizardData,
      dueDate: state.dueDate,
      dueTime: state.dueTime,
      source: state.source,
      createdBy: ref.read(loggedByProvider),
    );
    TemplatePickerModal.show(context, templateContext: ctx);
  }

  OrderCreationConfig _buildConfig() {
    return OrderCreationConfig(
      orderStateProvider: orderCreateStateProvider,
      posMode: false,
      enableDraft: true,
      enableCartSync: false,
      enableSwipeNavigation: true,
      createdByResolver: (ref) => ref.read(loggedByProvider),
      onStageChange: (stage) {
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            stage - 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      },
      stage1Builder: (ctx, controller) => Stage1ProductSelectionScreen(
        onContinue: () => controller.goToStage(2),
        orderStateProvider: orderCreateStateProvider,
      ),
      stage2Builder: (ctx, controller) => Stage2CustomerInfoScreen(
        onBack: () => controller.goToStage(1),
        onContinue: () => controller.goToStage(3),
        orderStateProvider: orderCreateStateProvider,
      ),
      stage3Builder: (ctx, controller) => Stage3DeliveryOptionsScreen(
        onBack: () => controller.goToStage(2),
        onContinue: () => controller.goToStage(4),
        orderStateProvider: orderCreateStateProvider,
      ),
      stage4Builder: (ctx, controller) => Stage4ReviewScreen(
        onBack: () => controller.goToStage(3),
        onSubmit: controller.submit,
        isProcessing: controller.isSubmitting,
        orderStateProvider: orderCreateStateProvider,
        onOpenTemplates: _openTemplatePicker,
      ),
      stageContainerBuilder: (ctx, stages, _) => PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: stages,
      ),
      onBeforeSubmit: (hookCtx) async {
        final state = hookCtx.state;
        var customerId = state.wizardData.selectedCustomer?.id;
        if (customerId == null &&
            state.wizardData.customerName.trim().isNotEmpty &&
            state.wizardData.customerPhone.trim().isNotEmpty) {
          try {
            final customerSvc = hookCtx.ref.read(customerServiceProvider);
            final result = await customerSvc.createCustomer(
              name: state.wizardData.customerName.trim(),
              phone: state.wizardData.customerPhone.trim(),
            );
            customerId = result.customer.id;
          } catch (e) {
            debugPrint('[OrderCreate] auto-create-customer failed: $e');
          }
        }
        return SubmitPreparation(customerId: customerId);
      },
      onAfterSubmit: (hookCtx, order) async {
        hookCtx.ref.read(orderDraftProvider.notifier).clear();
        hookCtx.ref.read(orderCreateStateProvider.notifier).reset();
        showTopSnackBar(hookCtx.context, OrdersLabels.orderCreated);
      },
      onNavigateAfterSubmit: (ctx, orderRef) {
        ctx.pushReplacement('/orders/$orderRef');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(OrdersLabels.createOrder),
        actions: [
          AppBarOverflowMenu(
            items: const [
              PopupMenuItem<String>(
                value: 'messageTemplates',
                child: Text(TemplatesLabels.overflowMenuOpenPicker),
              ),
            ],
            onSelected: (value) {
              if (value == 'messageTemplates') _openTemplatePicker();
            },
          ),
        ],
      ),
      body: OrderCreationOrchestrator(
        config: _buildConfig(),
      ),
    );
  }
}