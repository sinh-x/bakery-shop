import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/order_service.dart';
import '../../models/order_photo.dart';

class OrderPhotosNotifier extends AsyncNotifier<List<OrderPhoto>> {
  final String orderRef;

  OrderPhotosNotifier(this.orderRef);

  @override
  Future<List<OrderPhoto>> build() async {
    final service = ref.read(orderServiceProvider);
    return service.listOrderPhotos(orderRef);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(orderServiceProvider);
      return service.listOrderPhotos(orderRef);
    });
  }

  Future<OrderPhoto> upload(
    XFile file, {
    String tags = '',
    int? workItemId,
  }) async {
    final service = ref.read(orderServiceProvider);
    final photo = await service.uploadOrderPhoto(
      orderRef,
      file,
      tags: tags,
      workItemId: workItemId,
    );
    final current = state.value ?? [];
    state = AsyncData([...current, photo]);
    return photo;
  }

  Future<OrderPhoto> updateTags(int photoId, String tags) async {
    final service = ref.read(orderServiceProvider);
    final updated = await service.updatePhotoTags(orderRef, photoId, tags);
    final current = state.value ?? [];
    state = AsyncData(
      current.map((p) => p.id == photoId ? updated : p).toList(),
    );
    return updated;
  }

  Future<void> delete(int photoId) async {
    final service = ref.read(orderServiceProvider);
    await service.deleteOrderPhoto(orderRef, photoId);
    final current = state.value ?? [];
    state = AsyncData(current.where((p) => p.id != photoId).toList());
  }
}

final orderPhotosProvider =
    AsyncNotifierProvider.family<OrderPhotosNotifier, List<OrderPhoto>, String>(
      OrderPhotosNotifier.new,
    );