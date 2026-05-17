import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/catalog_browse_photo.dart';
import '../../../shared/services/image_download_metadata.dart';
import 'bulk_download_web.dart';
import 'bulk_common.dart';

/// Result of a bulk share operation.
class BulkShareResult {
  final int successCount;
  final int failCount;
  final bool usedBrowserDownloadFallback;
  final List<String> errors;

  const BulkShareResult({
    required this.successCount,
    required this.failCount,
    required this.usedBrowserDownloadFallback,
    this.errors = const [],
  });

  @override
  String toString() =>
      'BulkShareResult(success: $successCount, fail: $failCount)';
}

/// Service for bulk sharing catalog photos via the system share sheet.
class BulkShareService {
  BulkShareService(this._dio);

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

  /// Shares [photos] via a single system share sheet invocation.
  /// Photos are fetched in parallel batches of [parallelism] (default 4).
  /// Per-photo errors are caught individually and do not abort the batch.
  Future<BulkShareResult> share(List<CatalogBrowsePhoto> photos) async {
    const parallelism = 4;
    int successCount = 0;
    int failCount = 0;
    var usedBrowserDownloadFallback = false;
    final errors = <String>[];
    final allShareFiles = <XFile>[];
    final allWrittenFiles = <File>[];
    final downloadedPhotoBytesByPhotoId = <int, Uint8List>{};

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
            final bytes = await _fetchPhotoBytes(photo);
            return (bytes, null);
          } catch (e) {
            errors.add(
              '${photo.productName} #${photo.id}: không thể lấy ảnh — $e',
            );
            return (Uint8List(0), e);
          }
        }),
      );

      for (int i = 0; i < results.length; i++) {
        final (bytes, err) = results[i];
        final photo = chunkPhotos[i];
        if (err != null || bytes.isEmpty) {
          failCount++;
          continue;
        }
        try {
          downloadedPhotoBytesByPhotoId[photo.id] = bytes;
          final tempDir = await getTemporaryDirectory();
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
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(bytes);
          allWrittenFiles.add(file);
          allShareFiles.add(XFile(file.path, mimeType: metadata.mimeType));
        } catch (e) {
          failCount++;
          errors.add('${photo.productName} #${photo.id}: save failed — $e');
        }
      }
    }

    if (allShareFiles.isEmpty) {
      return BulkShareResult(
        successCount: 0,
        failCount: failCount,
        usedBrowserDownloadFallback: false,
        errors: errors,
      );
    }

    try {
      await Share.shareXFiles(allShareFiles, text: 'Tiệm Bánh Ninh Diêm');
      successCount = allShareFiles.length;
    } catch (e) {
      if (kIsWeb) {
        usedBrowserDownloadFallback = true;
        final fallbackService = BulkDownloadService(_dio);
        final photosWithBytes = photos
            .where(
              (photo) => downloadedPhotoBytesByPhotoId.containsKey(photo.id),
            )
            .toList();
        final fallback = await fallbackService.downloadFromBytes(
          photosWithBytes,
          downloadedPhotoBytesByPhotoId,
        );
        successCount = fallback.successCount;
        failCount += fallback.failCount;
        errors.addAll(fallback.errors);
        if (fallback.errors.isEmpty) {
          errors.add(
            'Không thể chia sẻ qua trình duyệt; đã chuyển sang tải xuống.',
          );
        }
      } else {
        failCount += allShareFiles.length;
        errors.add('Không thể chia sẻ qua trình duyệt: $e');
      }
    } finally {
      for (final f in allWrittenFiles) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    return BulkShareResult(
      successCount: successCount,
      failCount: failCount,
      usedBrowserDownloadFallback: usedBrowserDownloadFallback,
      errors: errors,
    );
  }
}

/// Provider family for BulkShareService.
final bulkShareServiceProvider = Provider.family<BulkShareService, Dio>(
  (ref, dio) => BulkShareService(dio),
);
