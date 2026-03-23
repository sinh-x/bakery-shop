import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/order_photo.dart';
import '../../../providers/order_providers.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

// ── Predefined tag definitions ─────────────────────────────────────────────────

class OrderPhotoTagDef {
  final String key;
  final String label;
  final Color color;

  const OrderPhotoTagDef({
    required this.key,
    required this.label,
    required this.color,
  });
}

const kOrderPhotoTags = [
  OrderPhotoTagDef(
    key: 'mau-trang-tri',
    label: 'Màu trang trí',
    color: Color(0xFF1565C0),
  ),
  OrderPhotoTagDef(
    key: 'chat-zalo',
    label: 'Chat Zalo',
    color: Color(0xFF0068FF),
  ),
  OrderPhotoTagDef(
    key: 'chat-messenger',
    label: 'Chat Messenger',
    color: Color(0xFF7B2D8B),
  ),
  OrderPhotoTagDef(
    key: 'chat-facebook',
    label: 'Chat Facebook',
    color: Color(0xFF1877F2),
  ),
  OrderPhotoTagDef(
    key: 'banh-hoan-thanh',
    label: 'Bánh hoàn thành',
    color: Color(0xFF2E7D32),
  ),
];

Set<String> _parseTags(String tags) {
  if (tags.isEmpty) return {};
  return tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toSet();
}

// ── Main gallery section ───────────────────────────────────────────────────────

/// Photo gallery section shown in Order Detail and Order Edit screens.
/// Reads from [orderPhotosProvider], supports upload, delete, and tag editing.
///
/// When [orderLevelOnly] is true, only shows photos with null [workItemId]
/// (i.e., order-level photos not linked to a specific work item).
class OrderPhotoSection extends ConsumerStatefulWidget {
  const OrderPhotoSection({
    super.key,
    required this.orderRef,
    required this.baseUrl,
    this.orderLevelOnly = false,
    this.workItemId,
  });

  final String orderRef;
  final String baseUrl;
  /// When true, only show photos with workItemId == null (order-level photos).
  final bool orderLevelOnly;
  /// When set, uploaded photos are linked to this work item ID.
  final int? workItemId;

  @override
  ConsumerState<OrderPhotoSection> createState() => _OrderPhotoSectionState();
}

class _OrderPhotoSectionState extends ConsumerState<OrderPhotoSection> {
  bool _uploading = false;
  final _picker = ImagePicker();

  Future<void> _pickAndUpload() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;

    setState(() => _uploading = true);
    try {
      for (final xfile in files) {
        await ref
            .read(orderPhotosProvider(widget.orderRef).notifier)
            .upload(File(xfile.path), workItemId: widget.workItemId);
      }
      if (mounted) {
        showTopSnackBar(context, VN.orderPhotoAdded);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deletePhoto(OrderPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.deleteOrderPhotoConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(VN.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(orderPhotosProvider(widget.orderRef).notifier)
          .delete(photo.id);
      if (mounted) {
        showTopSnackBar(context, VN.orderPhotoDeleted);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    }
  }

  Future<void> _editTags(OrderPhoto photo) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TagEditSheet(
        orderRef: widget.orderRef,
        photo: photo,
      ),
    );
  }

  void _openViewer(List<OrderPhoto> photos, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderPhotoViewer(
          photos: photos,
          initialIndex: initialIndex,
          baseUrl: widget.baseUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(orderPhotosProvider(widget.orderRef));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header with add button ─────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              VN.orderPhotos,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (_uploading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                tooltip: VN.addOrderPhoto,
                onPressed: _pickAndUpload,
                iconSize: 20,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),

        // ── Photo list ─────────────────────────────────────────────────
        photosAsync.when(
          loading: () => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              VN.apiError,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          data: (allPhotos) {
            final photos = widget.orderLevelOnly
                ? allPhotos.where((p) => p.workItemId == null).toList()
                : allPhotos;
            if (photos.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  VN.noOrderPhotos,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              );
            }
            return SizedBox(
              height: 134,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 4),
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, index) {
                  final photo = photos[index];
                  final url =
                      '${widget.baseUrl}/api/photos/${photo.photoHash}.jpg';
                  final tagKeys = _parseTags(photo.tags);

                  return GestureDetector(
                    onTap: () => _openViewer(photos, index),
                    onLongPress: () => _deletePhoto(photo),
                    child: SizedBox(
                      width: 90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Thumbnail with tag-edit overlay
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  url,
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                              // Label edit button
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _editTags(photo),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.label_outline,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Tag chips
                          if (tagKeys.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 2,
                              runSpacing: 2,
                              children: tagKeys.map((key) {
                                final tagDef = kOrderPhotoTags
                                    .where((t) => t.key == key)
                                    .firstOrNull;
                                final color = tagDef?.color ?? Colors.grey;
                                final label = tagDef?.label ?? key;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(30),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: color.withAlpha(100),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Full-screen viewer ─────────────────────────────────────────────────────────

/// Full-screen photo viewer — navigates pages, shows tag overlays.
/// Can be used from order detail, cake detail, and other screens.
class OrderPhotoViewer extends StatefulWidget {
  const OrderPhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.baseUrl,
  });

  final List<OrderPhoto> photos;
  final int initialIndex;
  final String baseUrl;

  @override
  State<OrderPhotoViewer> createState() => _OrderPhotoViewerState();
}

class _OrderPhotoViewerState extends State<OrderPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (ctx, index) {
          final photo = widget.photos[index];
          final url = '${widget.baseUrl}/api/photos/${photo.photoHash}.jpg';
          final tagKeys = _parseTags(photo.tags);

          return Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
              if (tagKeys.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: tagKeys.map((key) {
                        final tagDef =
                            kOrderPhotoTags.where((t) => t.key == key).firstOrNull;
                        final color = tagDef?.color ?? Colors.grey;
                        final label = tagDef?.label ?? key;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withAlpha(80),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Tag edit bottom sheet ──────────────────────────────────────────────────────

class _TagEditSheet extends ConsumerStatefulWidget {
  const _TagEditSheet({required this.orderRef, required this.photo});

  final String orderRef;
  final OrderPhoto photo;

  @override
  ConsumerState<_TagEditSheet> createState() => _TagEditSheetState();
}

class _TagEditSheetState extends ConsumerState<_TagEditSheet> {
  late Set<String> _selectedTags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedTags = _parseTags(widget.photo.tags);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final tags = _selectedTags.join(',');
      await ref
          .read(orderPhotosProvider(widget.orderRef).notifier)
          .updateTags(widget.photo.id, tags);
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, VN.photoTagsUpdated);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            VN.editPhotoTags,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kOrderPhotoTags.map((tag) {
              final selected = _selectedTags.contains(tag.key);
              return FilterChip(
                label: Text(tag.label),
                selected: selected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedTags.add(tag.key);
                    } else {
                      _selectedTags.remove(tag.key);
                    }
                  });
                },
                selectedColor: tag.color.withAlpha(50),
                checkmarkColor: tag.color,
                side: BorderSide(
                  color: selected ? tag.color : Colors.grey.shade300,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(VN.save),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
