import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/work_item_service.dart';
import '../../models/work_item.dart';
import 'order_detail_notifier.dart';

/// Result of a completed work-item mutation and its optional detail refresh.
///
/// A non-null [refreshError] means the server mutation succeeded and local
/// work-item state is authoritative, but the follow-up order-detail refresh
/// needs to be retried separately.
class WorkItemMutationOutcome {
  const WorkItemMutationOutcome({this.updatedItem, this.refreshError});

  final WorkItem? updatedItem;
  final Object? refreshError;

  bool get refreshFailed => refreshError != null;
}

class OrderWorkItemsNotifier extends AsyncNotifier<List<WorkItem>> {
  final String orderRef;

  OrderWorkItemsNotifier(this.orderRef);

  @override
  Future<List<WorkItem>> build() async {
    final service = ref.read(workItemServiceProvider);
    return service.listWorkItems(orderRef);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final service = ref.read(workItemServiceProvider);
      return service.listWorkItems(orderRef);
    });
  }

  Future<WorkItem> add({
    required String productName,
    String productId = '',
    int quantity = 1,
    double unitPrice = 0.0,
    String notes = '',
    int position = 0,
    bool isExtra = false,
    bool isGift = false,
    Map<String, dynamic>? attributes,
    int? priceChipId,
  }) async {
    final service = ref.read(workItemServiceProvider);
    final item = await service.createWorkItem(
      orderRef,
      productName: productName,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      notes: notes,
      position: position,
      isExtra: isExtra,
      isGift: isGift,
      attributes: attributes,
      priceChipId: priceChipId,
    );
    final current = state.value ?? [];
    state = AsyncData([...current, item]);
    await ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return item;
  }

  Future<WorkItem> edit(
    String itemId, {
    String? productName,
    String? productId,
    int? quantity,
    double? unitPrice,
    String? notes,
    int? position,
    bool? isBirthday,
    int? age,
    bool? isExtra,
    bool? isGift,
    Map<String, dynamic>? attributes,
    double? assignedPrice,
  }) async {
    final outcome = await _editWithOutcome(
      itemId,
      productName: productName,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      notes: notes,
      position: position,
      isBirthday: isBirthday,
      age: age,
      isExtra: isExtra,
      isGift: isGift,
      attributes: attributes,
      assignedPrice: assignedPrice,
    );
    return outcome.updatedItem!;
  }

  /// Replaces a product and reports a follow-up refresh failure separately.
  Future<WorkItemMutationOutcome> replaceProduct(
    String itemId, {
    required String productId,
    required String productName,
  }) =>
      _editWithOutcome(itemId, productId: productId, productName: productName);

  Future<WorkItemMutationOutcome> _editWithOutcome(
    String itemId, {
    String? productName,
    String? productId,
    int? quantity,
    double? unitPrice,
    String? notes,
    int? position,
    bool? isBirthday,
    int? age,
    bool? isExtra,
    bool? isGift,
    Map<String, dynamic>? attributes,
    double? assignedPrice,
  }) async {
    final service = ref.read(workItemServiceProvider);
    final updated = await service.updateWorkItem(
      orderRef,
      itemId,
      productName: productName,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      notes: notes,
      position: position,
      isBirthday: isBirthday,
      age: age,
      isExtra: isExtra,
      isGift: isGift,
      attributes: attributes,
      assignedPrice: assignedPrice,
    );
    final current = state.value ?? [];
    state = AsyncData(
      current.map((i) => i.id == itemId ? updated : i).toList(),
    );
    return WorkItemMutationOutcome(
      updatedItem: updated,
      refreshError: await retryOrderDetailRefresh(),
    );
  }

  Future<void> remove(String itemId) async {
    await removeWithOutcome(itemId);
  }

  /// Removes an item locally after DELETE succeeds and reports a later detail
  /// refresh failure without turning the successful deletion into an error.
  Future<WorkItemMutationOutcome> removeWithOutcome(String itemId) async {
    final service = ref.read(workItemServiceProvider);
    await service.deleteWorkItem(orderRef, itemId);
    final current = state.value ?? [];
    state = AsyncData(current.where((i) => i.id != itemId).toList());
    return WorkItemMutationOutcome(
      refreshError: await retryOrderDetailRefresh(),
    );
  }

  /// Retries only the order-detail reconciliation step.
  Future<Object?> retryOrderDetailRefresh() =>
      ref.read(orderDetailProvider(orderRef).notifier).refresh();

  /// Adds a blank assignment to a work item (DG-294 FR3/FR4).
  ///
  /// Calls the backend POST endpoint and optimistically appends the returned
  /// [BlankAssignment] to the matching [WorkItem] in the local cache.
  Future<BlankAssignment> addBlank(
    String itemId, {
    required int blankId,
    double quantity = 1.0,
    String notes = '',
  }) async {
    final service = ref.read(workItemServiceProvider);
    final assignment = await service.addBlank(
      orderRef,
      itemId,
      blankId: blankId,
      quantity: quantity,
      notes: notes,
    );
    _replaceItem(
      itemId,
      (item) => item.copyWith(blanks: [...item.blanks, assignment]),
    );
    return assignment;
  }

  /// Updates an existing blank assignment on a work item (DG-294 FR5).
  ///
  /// Calls the backend PATCH endpoint and replaces the matching
  /// [BlankAssignment] in the local cache with the server-returned value.
  Future<BlankAssignment> updateBlank(
    String itemId,
    int blankItemId, {
    double? quantity,
    String? notes,
  }) async {
    final service = ref.read(workItemServiceProvider);
    final updated = await service.updateBlank(
      orderRef,
      itemId,
      blankItemId,
      quantity: quantity,
      notes: notes,
    );
    _replaceItem(
      itemId,
      (item) => item.copyWith(
        blanks: item.blanks
            .map((b) => b.id == blankItemId ? updated : b)
            .toList(),
      ),
    );
    return updated;
  }

  /// Removes a blank assignment from a work item (DG-294 FR5).
  ///
  /// Calls the backend DELETE endpoint and removes the matching
  /// [BlankAssignment] from the local cache.
  Future<void> removeBlank(String itemId, int blankItemId) async {
    final service = ref.read(workItemServiceProvider);
    await service.deleteBlank(orderRef, itemId, blankItemId);
    _replaceItem(
      itemId,
      (item) => item.copyWith(
        blanks: item.blanks.where((b) => b.id != blankItemId).toList(),
      ),
    );
  }

  void _replaceItem(String itemId, WorkItem Function(WorkItem) update) {
    final current = state.value ?? [];
    state = AsyncData(
      current.map((i) => i.id == itemId ? update(i) : i).toList(),
    );
  }

  Future<WorkItem> transitionStatus(
    String itemId,
    String status, {
    String reason = '',
  }) async {
    final service = ref.read(workItemServiceProvider);
    final updated = await service.transitionStatus(
      orderRef,
      itemId,
      status,
      reason: reason,
    );
    final current = state.value ?? [];
    state = AsyncData(
      current.map((i) => i.id == itemId ? updated : i).toList(),
    );
    return updated;
  }
}

final orderWorkItemsProvider =
    AsyncNotifierProvider.family<
      OrderWorkItemsNotifier,
      List<WorkItem>,
      String
    >(OrderWorkItemsNotifier.new);
