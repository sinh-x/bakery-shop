import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api/api_client.dart';
import '../../data/models/knowledge_entry.dart';
import '../../data/providers/knowledge_provider.dart';
import '../../shared/services/image_download_metadata.dart';
import '../../shared/services/web_share_fallback_helpers.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'widgets/knowledge_photo_gallery.dart';

class KnowledgeDetailScreen extends ConsumerWidget {
  const KnowledgeDetailScreen({super.key, required this.entryId});

  final int entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(knowledgeEntryDetailProvider(entryId));

    return entryAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(actions: const [AppBarOverflowMenu()]),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(actions: const [AppBarOverflowMenu()]),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(VN.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.invalidate(knowledgeEntryDetailProvider(entryId)),
                child: const Text(VN.retry),
              ),
            ],
          ),
        ),
      ),
      data: (entry) {
        if (entry == null) {
          return Scaffold(
            appBar: AppBar(actions: const [AppBarOverflowMenu()]),
            body: const Center(child: Text(VN.apiError)),
          );
        }

        final typeLabel = VN.knowledgeTypes[entry.type] ?? entry.type;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(entry.title),
            actions: [
              _ShareEntryButton(entry: entry),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: VN.editKnowledge,
                onPressed: () => context.push('/knowledge/${entry.id}/edit'),
              ),
              AppBarOverflowMenu(
                onSelected: (value) async {
                  if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text(VN.confirmDeleteKnowledge),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text(VN.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                            ),
                            child: const Text(VN.deleteKnowledge),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref
                          .read(knowledgeEntriesProvider.notifier)
                          .deleteEntry(entry.id);
                      if (context.mounted) {
                        showTopSnackBar(context, VN.knowledgeDeleted);
                        context.pop();
                      }
                    }
                  }
                },
                items: [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          VN.deleteKnowledge,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Title with inline pin button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      entry.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    tooltip: entry.pinned ? 'Bỏ ghim' : 'Ghim',
                    onPressed: () async {
                      try {
                        final updated = await ref
                            .read(knowledgeEntriesProvider.notifier)
                            .pinEntry(entry.id, !entry.pinned);
                        ref.invalidate(knowledgeEntryDetailProvider(entryId));
                        if (context.mounted) {
                          showTopSnackBar(
                            context,
                            updated.pinned ? 'Đã ghim' : 'Đã bỏ ghim',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showTopSnackBar(context, 'Lỗi: $e');
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Type chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(typeLabel, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 12),

              // Tags
              if (entry.tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: entry.tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),

              if (entry.tags.isNotEmpty) const SizedBox(height: 16),

              // Photo gallery
              if (entry.photos.isNotEmpty) ...[
                KnowledgePhotoGallery(
                  photos: entry.photos,
                  baseUrl: ref.read(dioProvider).options.baseUrl,
                ),
                const SizedBox(height: 16),
              ],

              // Content
              if (entry.content.isNotEmpty)
                Text(entry.content, style: theme.textTheme.bodyLarge),

              const SizedBox(height: 16),

              // Updated at
              Text(
                'Cập nhật: ${formatDisplay(entry.updatedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}

class _ShareEntryButton extends ConsumerStatefulWidget {
  const _ShareEntryButton({required this.entry});

  final KnowledgeEntry entry;

  @override
  ConsumerState<_ShareEntryButton> createState() => _ShareEntryButtonState();
}

class _ShareEntryButtonState extends ConsumerState<_ShareEntryButton> {
  bool _sharing = false;

  static const _parallelism = 4;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final entry = widget.entry;
    final text = entry.content.isNotEmpty
        ? '${entry.title}\n\n${entry.content}'
        : entry.title;
    final dio = ref.read(dioProvider);
    final baseUrl = dio.options.baseUrl;
    try {
      if (entry.photos.isEmpty) {
        await SharePlus.instance.share(ShareParams(text: text));
        return;
      }

      final tmpDir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (final photo in entry.photos) {
        final bytes = await _fetchPhotoBytes(dio, baseUrl, photo);
        if (bytes == null) continue;
        final metadata = imageDownloadMetadata(bytes, sourceName: photo.url);
        final tmpFile = File(
          '${tmpDir.path}/${_knowledgePhotoFileName(photo, metadata)}',
        );
        await tmpFile.writeAsBytes(bytes);
        files.add(XFile(tmpFile.path, mimeType: metadata.mimeType));
      }

      if (files.isEmpty) {
        await SharePlus.instance.share(ShareParams(text: text));
        return;
      }

      await SharePlus.instance.share(
        ShareParams(files: files, text: text),
      );
    } catch (_) {
      if (!mounted) return;
      if (kIsWeb) {
        if (entry.photos.isEmpty) {
          await _copyTextFallback(text);
        } else {
          await _downloadPhotosFallback(text, entry.photos, baseUrl);
        }
      } else {
        showTopSnackBar(context, VN.khongTheChiaSe);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<Uint8List?> _fetchPhotoBytes(
    Dio dio,
    String baseUrl,
    KnowledgePhoto photo,
  ) async {
    final resp = await dio.get<List<int>>(
      '$baseUrl${photo.url}',
      options: Options(responseType: ResponseType.bytes),
    );
    if (resp.data == null) return null;
    return Uint8List.fromList(resp.data!);
  }

  String _knowledgePhotoFileName(
    KnowledgePhoto photo,
    ImageDownloadMetadata metadata,
  ) {
    final safeHash = photo.hash
        .replaceAll(RegExp(r'[\\/]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final baseName = safeHash.isEmpty ? 'knowledge_photo' : safeHash;
    return imageDownloadFileName(baseName, metadata);
  }

  Future<void> _copyTextFallback(String text) async {
    final copied = await WebShareFallbackHelpers.copyText(text);
    if (!mounted) return;
    if (copied) {
      showTopSnackBar(context, VN.daSaoChepNoiDung);
    } else {
      showTopSnackBar(context, VN.saoChepNoiDungThatBai);
    }
  }

  Future<void> _downloadPhotosFallback(
    String text,
    List<KnowledgePhoto> photos,
    String baseUrl,
  ) async {
    final fallbackResult = await _downloadPhotosForWeb(
      dio: ref.read(dioProvider),
      photos: photos,
      baseUrl: baseUrl,
    );
    if (!mounted) return;

    await _copyTextFallback(text);
    if (!mounted) return;

    if (mounted) {
      showTopSnackBar(
        context,
        VN.taiNAnh.replaceFirst(
          '{count}',
          '${fallbackResult.successCount}/${photos.length}',
        ),
      );
    }
    if (fallbackResult.errors.isNotEmpty) {
      if (!mounted) return;

      final errorMessage = fallbackResult.errors.length <= 2
          ? fallbackResult.errors.join('\n')
          : '${fallbackResult.failCount} ảnh không tải được: ${fallbackResult.errors.first}';

      if (!mounted) return;
      showTopSnackBar(
        context,
        'Lỗi: $errorMessage',
        backgroundColor: Colors.orange,
      );
    }
  }

  Future<PhotoDownloadResult> _downloadPhotosForWeb({
    required Dio dio,
    required List<KnowledgePhoto> photos,
    required String baseUrl,
  }) async {
    int successCount = 0;
    int failCount = 0;
    final errors = <String>[];

    for (
      int chunkStart = 0;
      chunkStart < photos.length;
      chunkStart += _parallelism
    ) {
      final chunkEnd = (chunkStart + _parallelism).clamp(0, photos.length);
      final chunkPhotos = photos.sublist(chunkStart, chunkEnd);
      final results = await Future.wait(
        chunkPhotos.map((photo) async {
          try {
            final bytes = await _fetchPhotoBytes(dio, baseUrl, photo);
            if (bytes == null || bytes.isEmpty) {
              return 'Ảnh ${photo.hash} không có dữ liệu';
            }
            final metadata = imageDownloadMetadata(
              bytes,
              sourceName: photo.url,
            );
            final downloaded = await WebShareFallbackHelpers.downloadBytes(
              bytes,
              _knowledgePhotoFileName(photo, metadata),
              mimeType: metadata.mimeType,
            );
            if (!downloaded) {
              return 'Không thể tải ảnh ${photo.hash}';
            }
            return null;
          } catch (e) {
            return 'Không thể tải ảnh ${photo.hash}: $e';
          }
        }),
      );

      for (final error in results) {
        if (error == null) {
          successCount++;
        } else {
          failCount++;
          errors.add(error);
        }
      }
    }

    return PhotoDownloadResult(
      successCount: successCount,
      failCount: failCount,
      errors: errors,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _sharing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.share),
      tooltip: VN.share,
      onPressed: _sharing ? null : _share,
    );
  }
}

class PhotoDownloadResult {
  const PhotoDownloadResult({
    required this.successCount,
    required this.failCount,
    required this.errors,
  });

  final int successCount;
  final int failCount;
  final List<String> errors;
}
