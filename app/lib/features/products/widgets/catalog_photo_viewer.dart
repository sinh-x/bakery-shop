import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/catalog_photo.dart';
import '../../../data/models/catalog_tag.dart';
import '../../../data/providers/catalog_provider.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/utils/xfile_utils.dart';
import '../../../shared/widgets/app_bar_overflow_menu.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import '../providers/catalog_photo_viewer_notifier.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'catalog_tag_chips.dart';
import 'catalog_tag_edit_sheet.dart';

/// Full-screen swipeable photo viewer for catalog photos.
///
/// Receives the initial photo list and index from the gallery grid.
/// Watches [catalogProvider] so caption edits are reflected immediately.
class CatalogPhotoViewer extends ConsumerStatefulWidget {
  const CatalogPhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.productId,
    required this.baseUrl,
  });

  final List<CatalogPhoto> photos;
  final int initialIndex;
  final int productId;
  final String baseUrl;

  @override
  ConsumerState<CatalogPhotoViewer> createState() => _CatalogPhotoViewerState();
}

class _CatalogPhotoViewerState extends ConsumerState<CatalogPhotoViewer> {
  late PageController _pageController;
  late final _viewerContext = catalogPhotoViewerContext(widget.productId);

  @override
  void initState() {
    super.initState();
    // Seed the viewer's current index from the initial photo. Deferred
    // to a microtask because Riverpod disallows provider mutation during
    // widget life-cycle hooks (initState/build).
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(catalogPhotoViewerProvider(_viewerContext).notifier)
          .reset(widget.initialIndex);
    });
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _downloadPhoto(List<CatalogPhoto> photos) async {
    final viewerNotifier = ref.read(
      catalogPhotoViewerProvider(_viewerContext).notifier,
    );
    final viewerState = ref.read(catalogPhotoViewerProvider(_viewerContext));
    if (viewerState.downloading || viewerState.currentIndex >= photos.length) {
      return;
    }
    viewerNotifier.setDownloading(true);
    final dio = ref.read(dioProvider);
    final photo = photos[viewerState.currentIndex];
    final url =
        '${widget.baseUrl}/api/products/${widget.productId}/catalog/${photo.id}/photo';
    try {
      final resp = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.data == null) throw Exception('No data');
      await Gal.putImageBytes(Uint8List.fromList(resp.data!));
      if (mounted) showTopSnackBar(context, ProductsLabels.daLuuAnh);
    } catch (e) {
      if (mounted) showTopSnackBar(context, ProductsLabels.khongTheTaiAnh);
    } finally {
      viewerNotifier.setDownloading(false);
    }
  }

  Future<void> _sharePhoto(List<CatalogPhoto> photos) async {
    final viewerNotifier = ref.read(
      catalogPhotoViewerProvider(_viewerContext).notifier,
    );
    final viewerState = ref.read(catalogPhotoViewerProvider(_viewerContext));
    if (viewerState.sharing || viewerState.currentIndex >= photos.length) {
      return;
    }
    viewerNotifier.setSharing(true);
    final dio = ref.read(dioProvider);
    final photo = photos[viewerState.currentIndex];
    final url =
        '${widget.baseUrl}/api/products/${widget.productId}/catalog/${photo.id}/photo';
    try {
      final resp = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.data == null) throw Exception('No data');
      final bytes = Uint8List.fromList(resp.data!);
      final xfile = await createXFileFromBytes(
        bytes,
        fileName: 'catalog_photo_${photo.id}.jpg',
        mimeType: 'image/jpeg',
      );
      await SharePlus.instance.share(
        ShareParams(files: [xfile], text: 'Tiệm Bánh Ninh Diêm'),
      );
    } catch (e) {
      if (mounted) showTopSnackBar(context, ProductsLabels.khongTheChiaSe);
    } finally {
      viewerNotifier.setSharing(false);
    }
  }

  void _openEditSheet(CatalogPhoto photo) {
    showEditCatalogTagsSheet(
      context: context,
      photo: photo,
      productId: widget.productId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogProvider(widget.productId));
    final photos = catalogAsync.value ?? widget.photos;
    final viewerState = ref.watch(catalogPhotoViewerProvider(_viewerContext));
    final viewerNotifier = ref.read(
      catalogPhotoViewerProvider(_viewerContext).notifier,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: photos.isEmpty
            ? null
            : Text(
                '${viewerState.currentIndex + 1} / ${photos.length}',
                style: const TextStyle(color: Colors.white),
              ),
        actions: [
          if (photos.isNotEmpty) ...[
            IconButton(
              icon: viewerState.downloading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download, color: Colors.white),
              tooltip: ProductsLabels.taiAnh,
              onPressed: viewerState.downloading
                  ? null
                  : () => _downloadPhoto(photos),
            ),
            IconButton(
              icon: viewerState.sharing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share, color: Colors.white),
              tooltip: ProductsLabels.chiaSe,
              onPressed: viewerState.sharing ? null : () => _sharePhoto(photos),
            ),
          ],
          AppBarOverflowMenu(
            onSelected: (value) {
              if (value == 'edit_photo' &&
                  viewerState.currentIndex < photos.length) {
                _openEditSheet(photos[viewerState.currentIndex]);
              }
            },
            items: photos.isEmpty
                ? const []
                : const [
                    PopupMenuItem<String>(
                      value: 'edit_photo',
                      child: Text(ProductsLabels.editCatalogPhoto),
                    ),
                  ],
          ),
        ],
      ),
      body: photos.isEmpty
          ? const Center(
              child: Icon(
                Icons.photo_library_outlined,
                color: Colors.white38,
                size: 64,
              ),
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: photos.length,
              onPageChanged: viewerNotifier.setCurrentIndex,
              itemBuilder: (ctx, index) {
                final photo = photos[index];
                final url =
                    '${widget.baseUrl}/api/products/${widget.productId}/catalog/${photo.id}/photo';
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, e, s) => const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                    if (photo.caption.isNotEmpty || photo.tags.isNotEmpty)
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (photo.caption.isNotEmpty)
                                Text(
                                  photo.caption,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                ),
                              if (photo.tags.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                CatalogTagChips(tags: photo.tags),
                              ],
                            ],
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

// ---------------------------------------------------------------------------
// Edit caption / tags bottom sheet
// ---------------------------------------------------------------------------

class _EditCaptionSheet extends ConsumerStatefulWidget {
  const _EditCaptionSheet({required this.photo, required this.productId});

  final CatalogPhoto photo;
  final int productId;

  @override
  ConsumerState<_EditCaptionSheet> createState() => _EditCaptionSheetState();
}

class _EditCaptionSheetState extends ConsumerState<_EditCaptionSheet> {
  late final TextEditingController _captionCtrl;
  late final _draftContext = catalogPhotoTagEditContext(
    widget.productId,
    widget.photo.id,
  );

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(
      catalogEditCaptionProvider(_draftContext).notifier,
    );
    final draft = ref.read(catalogEditCaptionProvider(_draftContext));
    _captionCtrl = TextEditingController(
      text: notifier.hasRetainedDraft ? draft.caption : widget.photo.caption,
    )..addListener(_persistCaption);
    // Seed the notifier with the photo's existing tags so the chip
    // selector reflects the initial selection without setState. Deferred
    // to a microtask because Riverpod disallows provider mutation during
    // widget life-cycle hooks (initState/build).
    Future.microtask(() {
      if (!mounted) return;
      final notifier = ref.read(
        catalogEditCaptionProvider(_draftContext).notifier,
      );
      notifier
        ..resetOperation()
        ..seed(widget.photo);
    });
  }

  @override
  void dispose() {
    _captionCtrl.removeListener(_persistCaption);
    _captionCtrl.dispose();
    super.dispose();
  }

  void _persistCaption() => ref
      .read(catalogEditCaptionProvider(_draftContext).notifier)
      .setCaption(_captionCtrl.text);

  Future<void> _save() async {
    final notifier = ref.read(
      catalogEditCaptionProvider(_draftContext).notifier,
    );
    final registry = ref.read(formDraftSessionProvider.notifier);
    final submittedDraft =
        ref.read(formDraftSessionProvider)[_draftContext]
            as CatalogEditCaptionState?;
    final catalogNotifier = ref.read(
      catalogProvider(widget.productId).notifier,
    );
    final caption = _captionCtrl.text.trim();
    final tags = ref
        .read(catalogEditCaptionProvider(_draftContext))
        .selectedTags
        .join(',');
    notifier.setSaving(true);
    try {
      await catalogNotifier.updatePhoto(
        widget.photo.id,
        caption: caption,
        tags: tags,
      );
      if (submittedDraft != null) {
        registry.clearDraftIfUnchanged(_draftContext, submittedDraft);
      }
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, ProductsLabels.catalogPhotoUpdated);
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? SharedLabels.apiError);
      }
    } finally {
      notifier.setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagDefsAsync = ref.watch(catalogTagDefsProvider);
    final captionState = ref.watch(catalogEditCaptionProvider(_draftContext));
    final notifier = ref.read(
      catalogEditCaptionProvider(_draftContext).notifier,
    );
    final initialTags = widget.photo.tags
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final isDirty =
        _captionCtrl.text != widget.photo.caption ||
        !setEquals(captionState.selectedTags, initialTags);

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
            ProductsLabels.editCatalogPhoto,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionCtrl,
            decoration: const InputDecoration(
              labelText: ProductsLabels.captionLabel,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              ProductsLabels.tagsLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          tagDefsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Row(
              children: [
                const Expanded(child: Text(SharedLabels.apiError)),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(catalogTagDefsProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text(SharedLabels.retry),
                ),
              ],
            ),
            data: (tagDefs) => _TagChipSelector(
              tagDefs: tagDefs,
              selectedTags: captionState.selectedTags,
              onToggle: notifier.toggleTag,
            ),
          ),
          const SizedBox(height: 16),
          DiscardFormDraftAction(
            isDirty: isDirty,
            onDiscard: () {
              _captionCtrl.text = widget.photo.caption;
              notifier.clear();
              notifier.seed(widget.photo);
            },
          ),
          FilledButton(
            onPressed: captionState.saving ? null : _save,
            child: captionState.saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(SharedLabels.save),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TagChipSelector extends StatelessWidget {
  const _TagChipSelector({
    required this.tagDefs,
    required this.selectedTags,
    required this.onToggle,
  });

  final List<CatalogTagDef> tagDefs;
  final Set<String> selectedTags;
  final void Function(String tag) onToggle;

  @override
  Widget build(BuildContext context) {
    final audience = tagDefs.where((t) => t.category == 'audience').toList();
    final occasion = tagDefs.where((t) => t.category == 'occasion').toList();
    final style = tagDefs.where((t) => t.category == 'style').toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (audience.isNotEmpty) ...[
          const Text(
            ProductsLabels.doiTuong,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          ...audience.map(
            (t) => FilterChip(
              label: Text(t.label, style: const TextStyle(fontSize: 12)),
              selected: selectedTags.contains(t.key),
              onSelected: (_) => onToggle(t.key),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
        if (occasion.isNotEmpty) ...[
          const Text(
            ProductsLabels.dip,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          ...occasion.map(
            (t) => FilterChip(
              label: Text(t.label, style: const TextStyle(fontSize: 12)),
              selected: selectedTags.contains(t.key),
              onSelected: (_) => onToggle(t.key),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
        if (style.isNotEmpty) ...[
          const Text(
            ProductsLabels.phongCach,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          ...style.map(
            (t) => FilterChip(
              label: Text(t.label, style: const TextStyle(fontSize: 12)),
              selected: selectedTags.contains(t.key),
              onSelected: (_) => onToggle(t.key),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }
}
