import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Compact photo picker for the quick-log event form (FR6).
///
/// Shows a single "Add photos" button by default; expands to a compact
/// thumbnail strip when photos are selected. Designed to keep the
/// dashboard quick-log form compact (NFR1 — upload happens after event
/// creation; the parent sets [uploading] while uploading).
///
/// Newly-picked files are reported via [onSelectionChanged]; the parent
/// owns the upload lifecycle and reads the final list at submit time.
class QuickLogPhotoPicker extends StatefulWidget {
  const QuickLogPhotoPicker({
    super.key,
    required this.selectedPhotos,
    required this.onSelectionChanged,
    this.uploading = false,
  });

  /// Newly-picked local files not yet uploaded.
  final List<XFile> selectedPhotos;

  /// Called whenever the user adds or removes a locally-picked photo.
  final ValueChanged<List<XFile>> onSelectionChanged;

  /// When true, the add button is disabled and an upload spinner is shown.
  final bool uploading;

  @override
  State<QuickLogPhotoPicker> createState() => _QuickLogPhotoPickerState();
}

class _QuickLogPhotoPickerState extends State<QuickLogPhotoPicker> {
  final _picker = ImagePicker();

  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    widget.onSelectionChanged([...widget.selectedPhotos, ...files]);
  }

  void _removeAt(int index) {
    final next = [...widget.selectedPhotos]..removeAt(index);
    widget.onSelectionChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.selectedPhotos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (count > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: count,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final file = widget.selectedPhotos[index];
                  return _CompactThumb(
                    file: file,
                    onRemove: () => _removeAt(index),
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: widget.uploading ? null : _pickPhotos,
              icon: const Icon(Icons.add_a_photo, size: 18),
              label: Text(
                count > 0 ? '${VN.addEventPhoto} ($count)' : VN.addEventPhoto,
              ),
            ),
            if (widget.uploading) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 6),
              Text(VN.uploadingPhotos, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ],
    );
  }
}

class _CompactThumb extends StatelessWidget {
  const _CompactThumb({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(file.path),
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 10,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
