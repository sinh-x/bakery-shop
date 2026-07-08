import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/customer_service.dart';
import '../../data/api/order_service.dart';
import '../../data/api/work_item_service.dart';
import '../../providers/events_provider.dart';
import '../../providers/order/order_create_state_provider.dart';
import '../../providers/order_providers.dart';
import '../../shared/utils/api_error.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'widgets/order_stage_indicator.dart';
import 'widgets/gated_page_physics.dart';
import 'widgets/order_wizard.dart';
import 'widgets/stage1_product_selection_screen.dart';
import 'widgets/stage2_customer_info_screen.dart';
import 'widgets/stage3_delivery_options_screen.dart';
import 'widgets/stage4_review_screen.dart';

class OrderCreateScreen extends ConsumerStatefulWidget {
  const OrderCreateScreen({super.key});

  @override
  ConsumerState<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends ConsumerState<OrderCreateScreen> {
  late final PageController _pageController;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _restoreDraft();
  }

  @override
  void deactivate() {
    _saveDraft();
    super.deactivate();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _restoreDraft() {
    final draft = ref.read(orderDraftProvider);
    if (draft == null) return;
    final notifier = ref.read(orderCreateStateProvider.notifier);
    final data = OrderWizardData(
      customerName: draft.customerName,
      customerPhone: draft.customerPhone,
      deliveryType: draft.deliveryType,
      deliveryAddress: draft.deliveryAddress,
      deliveryPhone: draft.deliveryPhone,
      shippingFee: draft.shippingFee,
      notes: draft.notes,
    );
    notifier.updateWizardData(data);
    notifier.updateItems(List.of(draft.items));
    notifier.updateDueDate(draft.dueDate);
    notifier.updateDueTime(draft.dueTime);
    notifier.updateSource(draft.source);
    notifier.updateSelectedCategorySlug(draft.selectedCategorySlug);
    if (draft.customerId != null) {
      notifier.restoreCustomerFromDraft(draft.customerId!);
    }
    final targetStage = draft.currentStage.clamp(1, 4);
    notifier.goToStage(targetStage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetStage - 1);
      }
    });
  }

  void _saveDraft() {
    if (_submitted) return;
    final state = ref.read(orderCreateStateProvider);
    final draft = OrderDraft(
      customerName: state.wizardData.customerName,
      customerPhone: state.wizardData.customerPhone,
      deliveryPhone: state.wizardData.deliveryPhone,
      items: List.of(state.items),
      dueDate: state.dueDate,
      dueTime: state.dueTime,
      deliveryType: state.wizardData.deliveryType,
      deliveryAddress: state.wizardData.deliveryAddress,
      shippingFee: state.wizardData.shippingFee,
      notes: state.wizardData.notes,
      source: state.source,
      currentStage: state.currentStage,
      selectedCategorySlug: state.selectedCategorySlug,
      customerId: state.wizardData.selectedCustomer?.id,
    );
    if (draft.isNotEmpty) {
      ref.read(orderDraftProvider.notifier).save(draft);
    } else {
      ref.read(orderDraftProvider.notifier).clear();
    }
  }

  void _goToStage(int stage) {
    _saveDraft();
    ref.read(orderCreateStateProvider.notifier).goToStage(stage);
    _pageController.animateToPage(
      stage - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _submitOrder() async {
    if (_submitting) return;
    final state = ref.read(orderCreateStateProvider);
    if (state.items.isEmpty) {
      showTopSnackBar(context, OrdersLabels.validationSelectAtLeastOneProduct);
      return;
    }

    setState(() => _submitting = true);
    try {
      final service = ref.read(orderServiceProvider);
      final staffName = ref.read(loggedByProvider);
      final customerName = state.wizardData.customerName.isEmpty
          ? OrdersLabels.walkInCustomerFallback
          : state.wizardData.customerName;

      var customerId = state.wizardData.selectedCustomer?.id;
      if (customerId == null &&
          state.wizardData.customerName.trim().isNotEmpty &&
          state.wizardData.customerPhone.trim().isNotEmpty) {
        try {
          final customerSvc = ref.read(customerServiceProvider);
          final result = await customerSvc.createCustomer(
            name: state.wizardData.customerName.trim(),
            phone: state.wizardData.customerPhone.trim(),
          );
          customerId = result.customer.id;
        } catch (e) {
          debugPrint('[OrderCreate] _submitOrder auto-create-customer failed: $e');
        }
      }

      final newOrder = await service.createOrder(
        customerName: customerName,
        customerPhone: state.wizardData.customerPhone,
        customerId: customerId,
        items: state.items.map((i) {
          final m = <String, dynamic>{
            'productId': i.product.id.toString(),
            'productName': i.product.name,
            'quantity': i.quantity,
            'unitPrice': i.unitPrice,
            'notes': i.notes,
            'isBirthday': i.isBirthday,
            'isExtra': i.isExtra,
            'isGift': i.isGift,
            'attributes': i.attributes,
            'priceChipId': i.priceChipId,
          };
          if (i.isBirthday && i.age.isNotEmpty) {
            final age = int.tryParse(i.age.trim());
            if (age != null) m['age'] = age;
          }
          return m;
        }).toList(),
        shippingFee: state.wizardData.shippingFee,
        dueDate: state.dueDate != null ? formatApiDate(state.dueDate!) : null,
        dueTime: state.dueTime != null
            ? formatHourMinute(state.dueTime!.hour, state.dueTime!.minute)
            : null,
        deliveryType: state.wizardData.deliveryType,
        deliveryAddress: state.wizardData.deliveryAddress,
        deliveryPhone: state.wizardData.deliveryPhone,
        notes: state.wizardData.notes.trim(),
        source: state.source.isEmpty ? null : state.source,
        createdBy: staffName,
      );

      final hasPerItemPhotos = state.items.any(
        (i) => i.pendingPhotos.isNotEmpty,
      );
      if (hasPerItemPhotos) {
        final workItemSvc = ref.read(workItemServiceProvider);
        final workItems = await workItemSvc.listWorkItems(newOrder.orderRef);
        workItems.sort((a, b) => a.position.compareTo(b.position));

        int totalPhotos = 0;
        int failedPhotos = 0;
        for (var idx = 0; idx < state.items.length; idx++) {
          final draftItem = state.items[idx];
          if (draftItem.pendingPhotos.isEmpty) continue;
          final workItemId = idx < workItems.length
              ? int.tryParse(workItems[idx].id)
              : null;
          for (final xfile in draftItem.pendingPhotos) {
            totalPhotos++;
            try {
              await service.uploadOrderPhoto(
                newOrder.orderRef,
                xfile,
                workItemId: workItemId,
              );
            } catch (e) {
              failedPhotos++;
              debugPrint('Photo upload failed (${xfile.path}): $e');
            }
          }
        }
        if (failedPhotos > 0 && mounted) {
          showTopSnackBar(
            context,
            OrdersLabels.photoUploadResult(
              totalPhotos - failedPhotos,
              totalPhotos,
              failedPhotos,
            ),
          );
        }
      }

      await ref.read(orderListProvider.notifier).refresh();

      if (mounted) {
        _submitted = true;
        ref.read(orderDraftProvider.notifier).clear();
        ref.read(orderCreateStateProvider.notifier).reset();
        showTopSnackBar(context, VN.orderCreated);
        context.push('/orders/${newOrder.orderRef}');
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, normalizeApiError(e).message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderCreateStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.createOrder),
        actions: const [AppBarOverflowMenu()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: OrderStageIndicator(
              currentStage: state.currentStage,
              onStageTap: (s) => state.canNavigateToStage(s) ? _goToStage(s) : null,
            ),
          ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: _onSwipe,
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  Stage1ProductSelectionScreen(onContinue: _goToStage2),
                  Stage2CustomerInfoScreen(onBack: _goToStage1, onContinue: _goToStage3),
                  Stage3DeliveryOptionsScreen(onBack: _goToStage2, onContinue: _goToStage4),
                  Stage4ReviewScreen(onBack: _goToStage3, onSubmit: _submitOrder, isProcessing: _submitting),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onSwipe(DragEndDetails d) {
    final s = ref.read(orderCreateStateProvider);
    final pv = d.primaryVelocity;
    final target = targetStageForSwipe(
      velocity: Velocity(pixelsPerSecond: pv == null ? Offset.zero : Offset(pv, 0)),
      currentStage: s.currentStage, pageCount: 4);
    if (target != null && s.canNavigateToStage(target)) _goToStage(target);
  }

  void _goToStage1() => _goToStage(1);
  void _goToStage2() => _goToStage(2);
  void _goToStage3() => _goToStage(3);
  void _goToStage4() => _goToStage(4);
}
