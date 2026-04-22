import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/catalog_browse_photo.dart';

/// Sanitize [input] for use in a file name.
/// Replaces invalid characters with underscores, strips path traversal,
/// and limits total length to 100 chars.
String _safeFileName(String input) {
  final sanitized = input
      .replaceAll(RegExp(r'[^\w\s\-]'), '_')
      .replaceAll(RegExp(r'[\/\\]'), '_')
      .replaceAll(RegExp(r'\.\.'), '_')
      .trim();
  // Clamp at 100 chars, avoiding surrogate pair boundary splits
  if (sanitized.length > 100) {
    return sanitized.substring(0, sanitized.length.clamp(0, 100));
  }
  return sanitized.isEmpty ? 'photo' : sanitized;
}

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
    final allShareFiles = <XFile>[];
    final allWrittenFiles = <File>[];

    final futures = photos.map((photo) async {
      try {
        final bytes = await _fetchPhotoBytes(photo);
        return (bytes, null);
      } catch (e) {
        errors.add('${photo.productName} #${photo.id}: fetch failed — $e');
        return (Uint8List(0), e);
      }
    });

    final chunks = _chunkedFutures(futures, parallelism);
    for (final chunk in chunks) {
      final results = await Future.wait(chunk);
      final shareFiles = <XFile>[];
      final writtenFiles = <File>[];

      for (int i = 0; i < results.length; i++) {
        final (bytes, err) = results[i];
        if (err != null) {
          failCount++;
        } else if (bytes.isEmpty) {
          failCount++;
        } else {
          try {
            final tempDir = await getTemporaryDirectory();
            final safeName = _safeFileName(photos[i].productName);
            final fileName = '${safeName}_${photos[i].id}.jpg';
            final file = File('${tempDir.path}/$fileName');
            await file.writeAsBytes(bytes);
            writtenFiles.add(file);
            shareFiles.add(XFile(file.path));
          } catch (e) {
            failCount++;
            errors.add('${photos[i].productName} #${photos[i].id}: save failed — $e');
          }
        }
      }

      // Accumulate files for the single share invocation at the end
      allShareFiles.addAll(shareFiles);
      allWrittenFiles.addAll(writtenFiles);
    }

    if (allShareFiles.isEmpty) {
      return BulkShareResult(
        successCount: 0,
        failCount: failCount,
        errors: errors,
      );
    }

    try {
      await Share.shareXFiles(allShareFiles, text: 'Tiệm Bánh Ninh Diêm');
      successCount = allShareFiles.length;
    } catch (e) {
      failCount += allShareFiles.length;
      errors.add('Share sheet error: $e');
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
      errors: errors,
    );
  }

  List<List<Future<(Uint8List, Object?)>>> _chunkedFutures(
    Iterable<Future<(Uint8List, Object?)>> futures,
    int size,
  ) {
    final chunks = <List<Future<(Uint8List, Object?)>>>[];
    final iterator = futures.iterator;
    while (iterator.moveNext()) {
      final chunk = <Future<(Uint8List, Object?)>>[];
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
