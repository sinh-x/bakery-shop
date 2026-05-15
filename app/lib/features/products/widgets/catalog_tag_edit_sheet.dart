import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_photo.dart';
import '../../../data/models/catalog_tag.dart';
import '../../../providers/catalog_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';

/// Shared bottom sheet for editing a catalog photo's caption and tags.
///
/// Use `showEditCatalogTagsSheet` to display from any context.
class EditCatalogTagsSheet extends ConsumerStatefulWidget {
  const EditCatalogTagsSheet({
    super.key,
    required this.photo,
    required this.productId,
  });

  final CatalogPhoto photo;
  final int productId;

  @override
  ConsumerState<EditCatalogTagsSheet> createState() =>
      _EditCatalogTagsSheetState();
}

class _EditCatalogTagsSheetState
    extends ConsumerState<EditCatalogTagsSheet> {
  late final TextEditingController _captionCtrl;
  final Set<String> _selectedTags = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _captionCtrl = TextEditingController(text: widget.photo.caption);
    if (widget.photo.tags.isNotEmpty) {
      _selectedTags.addAll(
        widget.photo.tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
      );
    }
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(catalogProvider(widget.productId).notifier)
          .updatePhoto(
            widget.photo.id,
            caption: _captionCtrl.text.trim(),
            tags: _selectedTags.join(','),
          );
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, VN.catalogPhotoUpdated);
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? VN.apiError);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagDefsAsync = ref.watch(catalogTagDefsProvider);

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
            VN.editCatalogPhoto,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionCtrl,
            decoration: const InputDecoration(labelText: VN.captionLabel),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              VN.tagsLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          tagDefsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Row(
              children: [
                const Expanded(child: Text(VN.apiError)),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(catalogTagDefsProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text(VN.retry),
                ),
              ],
            ),
            data: (tagDefs) => TagChipSelector(
              tagDefs: tagDefs,
              selectedTags: _selectedTags,
              onToggle: (tag) {
                setState(() {
                  if (_selectedTags.contains(tag)) {
                    _selectedTags.remove(tag);
                  } else {
                    _selectedTags.add(tag);
                  }
                });
              },
            ),
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

/// Tag chip selector widget with audience/occasion/style grouping.
///
/// Public so it can be reused independently of the sheet.
class TagChipSelector extends StatelessWidget {
  const TagChipSelector({
    super.key,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (audience.isNotEmpty) ...[
          const Text(VN.doiTuong,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: audience
                .map((t) => FilterChip(
                      label: Text(t.label, style: const TextStyle(fontSize: 12)),
                      selected: selectedTags.contains(t.key),
                      onSelected: (_) => onToggle(t.key),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (occasion.isNotEmpty) ...[
          const Text(VN.dip,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: occasion
                .map((t) => FilterChip(
                      label: Text(t.label, style: const TextStyle(fontSize: 12)),
                      selected: selectedTags.contains(t.key),
                      onSelected: (_) => onToggle(t.key),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (style.isNotEmpty) ...[
          const Text(VN.phongCach,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: style
                .map((t) => FilterChip(
                      label: Text(t.label, style: const TextStyle(fontSize: 12)),
                      selected: selectedTags.contains(t.key),
                      onSelected: (_) => onToggle(t.key),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

/// Convenience function to show the edit catalog tags bottom sheet.
void showEditCatalogTagsSheet({
  required BuildContext context,
  required CatalogPhoto photo,
  required int productId,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => EditCatalogTagsSheet(
      photo: photo,
      productId: productId,
    ),
  );
}
