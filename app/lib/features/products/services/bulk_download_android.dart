import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/models/catalog_browse_photo.dart';
import 'bulk_common.dart';

/// Result of a bulk download operation.
class BulkDownloadResult {
  final int successCount;
  final int failCount;
  final List<String> errors;

  const BulkDownloadResult({
    required this.successCount,
    required this.failCount,
    this.errors = const [],
  });

  @override
  String toString() =>
      'BulkDownloadResult(success: $successCount, fail: $failCount)';
}

/// Android implementation of bulk download using Gal plugin.
class BulkDownloadService {
  BulkDownloadService(this._dio);

  final Dio _dio;

  Future<Uint8List> _fetchPhotoBytes(CatalogBrowsePhoto photo) async {
    final productId = photo.productId;
    final id = photo.id;
    final url =
        '${_dio.options.baseUrl}/api/products/$productId/catalog/$id/photo';
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? []);
  }

  /// Downloads [photos] to the device gallery using Gal.
  /// Bounded parallelism of 4 concurrent HTTP requests.
  /// Per-photo errors are caught individually and do not crash the batch.
  Future<BulkDownloadResult> download(List<CatalogBrowsePhoto> photos) async {
    const parallelism = 4;
    int successCount = 0;
    int failCount = 0;
    final errors = <String>[];

    for (int chunkStart = 0; chunkStart < photos.length; chunkStart += parallelism) {
      final chunkEnd = (chunkStart + parallelism).clamp(0, photos.length);
      final chunkPhotos = photos.sublist(chunkStart, chunkEnd);
      final results = await Future.wait(chunkPhotos.map((photo) async {
        try {
          final bytes = await _fetchPhotoBytes(photo);
          final tempDir = await getTemporaryDirectory();
          final fileName = catalogPhotoFileName(
            productName: photo.productName,
            productId: photo.productId,
            photoId: photo.id,
          );
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(bytes);
          try {
            await Gal.putImage(file.path, album: 'Bakery');
            return true;
          } finally {
            try {
              await file.delete();
            } catch (_) {}
          }
        } catch (e) {
          errors.add('${photo.productName} #${photo.id}: save failed — $e');
          return false;
        }
      }));

      for (final ok in results) {
        if (ok) {
          successCount++;
        } else {
          failCount++;
        }
      }
    }

    return BulkDownloadResult(
      successCount: successCount,
      failCount: failCount,
      errors: errors,
    );
  }
}

/// Provider family for BulkDownloadService.
final bulkDownloadServiceProvider =
    Provider.family<BulkDownloadService, Dio>((ref, dio) {
  return BulkDownloadService(dio);
});
