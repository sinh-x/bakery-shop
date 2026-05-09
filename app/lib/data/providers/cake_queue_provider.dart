import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/work_item_service.dart';
import '../models/cake_queue_item.dart';

class CakeQueueNotifier extends AsyncNotifier<List<CakeQueueItem>> {
  final bool includeReady;

  CakeQueueNotifier(this.includeReady);

  @override
  Future<List<CakeQueueItem>> build() async {
    final service = ref.read(workItemServiceProvider);
    return service.listCakeQueue(includeReady: includeReady);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(workItemServiceProvider);
      return service.listCakeQueue(includeReady: includeReady);
    });
  }
}

final cakeQueueProvider =
    AsyncNotifierProvider.family<CakeQueueNotifier, List<CakeQueueItem>, bool>(
  CakeQueueNotifier.new,
);

/// Delivery queue — work items with status = 'ready', sorted by due date.
class DeliveryQueueNotifier extends AsyncNotifier<List<CakeQueueItem>> {
  @override
  Future<List<CakeQueueItem>> build() async {
    final service = ref.read(workItemServiceProvider);
    final all = await service.listCakeQueue(includeReady: true);
    return all.where((item) => item.status == 'ready').toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(workItemServiceProvider);
      final all = await service.listCakeQueue(includeReady: true);
      return all.where((item) => item.status == 'ready').toList();
    });
  }
}

final deliveryQueueProvider =
    AsyncNotifierProvider<DeliveryQueueNotifier, List<CakeQueueItem>>(
  DeliveryQueueNotifier.new,
);
