import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/catalog_browse_photo.dart';

/// Result of a bulk share operation.
class BulkShareResult {
  final int successCount;
  final int failCount;
  final List<String> errors;

  const BulkShareResult({
    required this.successCount,
    required this.failCount,
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
    final errors = <String>[];

    final futures = photos.map((photo) async {
      try {
        final bytes = await _fetchPhotoBytes(photo);
        return bytes;
      } catch (e) {
        return Uint8List(0);
      }
    });

    final chunks = _chunkedFutures(futures, parallelism);
    for (final chunk in chunks) {
      final results = await Future.wait(chunk);
      final shareFiles = <XFile>[];

      for (int i = 0; i < results.length; i++) {
        final bytes = results[i];
        if (bytes.isEmpty) {
          failCount++;
          errors.add('${photos[i].productName} #${photos[i].id}: download failed');
        } else {
          try {
            final tempDir = await getTemporaryDirectory();
            final fileName = '${photos[i].productName}_${photos[i].id}.jpg';
            final file = File('${tempDir.path}/$fileName');
            await file.writeAsBytes(bytes);
            shareFiles.add(XFile(file.path));
          } catch (e) {
            failCount++;
            errors.add('${photos[i].productName} #${photos[i].id}: save failed');
          }
        }
      }

      if (shareFiles.isNotEmpty) {
        try {
          await Share.shareXFiles(
            shareFiles,
            text: 'Tiệm Bánh Ninh Diêm',
          );
          successCount += shareFiles.length;
        } catch (e) {
          failCount += shareFiles.length;
          errors.add('Share sheet error: $e');
        }
      }
    }

    return BulkShareResult(
      successCount: successCount,
      failCount: failCount,
      errors: errors,
    );
  }

  List<List<Future<Uint8List>>> _chunkedFutures(
    Iterable<Future<Uint8List>> futures,
    int size,
  ) {
    final chunks = <List<Future<Uint8List>>>[];
    final iterator = futures.iterator;
    while (iterator.moveNext()) {
      final chunk = <Future<Uint8List>>[];
      for (int i = 0; i < size && iterator.moveNext(); i++) {
        chunk.add(iterator.current);
      }
      chunks.add(chunk);
    }
    return chunks;
  }
}

/// Provider family for BulkShareService.
final bulkShareServiceProvider =
    Provider.family<BulkShareService, Dio>((ref, dio) => BulkShareService(dio));
