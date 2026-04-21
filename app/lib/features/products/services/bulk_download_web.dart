import 'dart:typed_data';
import 'dart:html' as html;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_browse_photo.dart';

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
    const parallelism = 4;
    int successCount = 0;
    int failCount = 0;
    final errors = <String>[];

    final futures = photos.map((photo) async {
      try {
        final bytes = await _fetchPhotoBytes(photo);
        _triggerDownload(
          bytes,
          '${photo.productName}_${photo.id}.jpg',
          'image/jpeg',
        );
        return true;
      } catch (e) {
        return false;
      }
    });

    final chunks = _chunkedFutures(futures, parallelism);
    for (final chunk in chunks) {
      final results = await Future.wait(chunk);
      for (int i = 0; i < results.length; i++) {
        if (results[i]) {
          successCount++;
        } else {
          failCount++;
          errors.add('${photos[i].productName} #${photos[i].id}: download failed');
        }
      }
    }

    return BulkDownloadResult(
      successCount: successCount,
      failCount: failCount,
      errors: errors,
    );
  }

  void _triggerDownload(Uint8List bytes, String fileName, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  List<List<Future<bool>>> _chunkedFutures(
    Iterable<Future<bool>> futures,
    int size,
  ) {
    final chunks = <List<Future<bool>>>[];
    final iterator = futures.iterator;
    while (iterator.moveNext()) {
      final chunk = <Future<bool>>[];
      for (int i = 0; i < size && iterator.moveNext(); i++) {
        chunk.add(iterator.current);
      }
      chunks.add(chunk);
    }
    return chunks;
  }
}

/// Provider family for BulkDownloadService.
final bulkDownloadServiceProvider =
    Provider.family<BulkDownloadService, Dio>((ref, dio) {
  return BulkDownloadService(dio);
});
