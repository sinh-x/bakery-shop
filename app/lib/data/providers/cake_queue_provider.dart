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
  (includeReady) => CakeQueueNotifier(includeReady),
);
