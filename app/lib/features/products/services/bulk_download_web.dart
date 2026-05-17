import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_browse_photo.dart';
import '../../../shared/services/image_download_metadata.dart';
import '../../../shared/services/web_share_fallback_helpers.dart';
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

/// Web implementation of bulk download via browser per-file download.
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

  /// Downloads [photos] to the browser downloads folder.
  /// Bounded parallelism of 4 concurrent HTTP requests.
  /// Per-photo errors are caught individually and do not crash the batch.
  Future<BulkDownloadResult> download(List<CatalogBrowsePhoto> photos) async {
    return _downloadFromSources(
      photos,
      (photo) async => await _fetchPhotoBytes(photo),
      includePhotoName: (photo, bytes) => bytes.isEmpty,
      makeMessage: (photo, error) =>
          '${photo.productName} #${photo.id}: không thể tải xuống ảnh — $error',
      fetchFailureMessage: (photo) =>
          '${photo.productName} #${photo.id}: không có dữ liệu ảnh để tải',
    );
  }

  /// Downloads [photos] from pre-fetched bytes when available.
  Future<BulkDownloadResult> downloadFromBytes(
    List<CatalogBrowsePhoto> photos,
    Map<int, Uint8List> photoBytesByPhotoId,
  ) async {
    return _downloadFromSources(
      photos,
      (photo) async => photoBytesByPhotoId[photo.id] ?? Uint8List(0),
      includePhotoName: (photo, bytes) => bytes.isEmpty,
      makeMessage: (photo, error) =>
          '${photo.productName} #${photo.id}: không thể tải từ bộ nhớ tạm — $error',
      fetchFailureMessage: (photo) =>
          '${photo.productName} #${photo.id}: thiếu dữ liệu đã tải trước',
    );
  }

  Future<BulkDownloadResult> _downloadFromSources(
    List<CatalogBrowsePhoto> photos,
    Future<Uint8List> Function(CatalogBrowsePhoto) fetchBytes, {
    required bool Function(CatalogBrowsePhoto, Uint8List) includePhotoName,
    required String Function(CatalogBrowsePhoto, String) makeMessage,
    required String Function(CatalogBrowsePhoto) fetchFailureMessage,
  }) async {
    const parallelism = 4;
    int successCount = 0;
    int failCount = 0;
    final errors = <String>[];

    for (
      int chunkStart = 0;
      chunkStart < photos.length;
      chunkStart += parallelism
    ) {
      final chunkEnd = (chunkStart + parallelism).clamp(0, photos.length);
      final chunkPhotos = photos.sublist(chunkStart, chunkEnd);
      final results = await Future.wait(
        chunkPhotos.map((photo) async {
          try {
            final bytes = await fetchBytes(photo);
            if (includePhotoName(photo, bytes)) {
              errors.add(fetchFailureMessage(photo));
              return false;
            }

            final metadata = imageDownloadMetadata(
              bytes,
              sourceName: photo.filePath,
            );
            final fileName = catalogPhotoFileName(
              productName: photo.productName,
              productId: photo.productId,
              photoId: photo.id,
              extension: metadata.extension,
            );
            final downloaded = await WebShareFallbackHelpers.downloadBytes(
              bytes,
              fileName,
              mimeType: metadata.mimeType,
            );
            if (!downloaded) {
              errors.add('$fileName: trình duyệt không thể bắt đầu tải ảnh');
              return false;
            }
            return true;
          } catch (e) {
            errors.add(makeMessage(photo, e.toString()));
            return false;
          }
        }),
      );

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
final bulkDownloadServiceProvider = Provider.family<BulkDownloadService, Dio>((
  ref,
  dio,
) {
  return BulkDownloadService(dio);
});
