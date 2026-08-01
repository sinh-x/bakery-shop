import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/event_photo.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Photo picker + preview section for the event create/edit form.
///
/// Shows existing event photos (fetched via `EventService.getEventPhotos`)
/// alongside newly-picked local files ([XFile]). Newly-picked files are
/// reported to the parent via [onSelectionChanged] for upload after the
/// event is created or updated.
///
/// Extracted from `event_form_screen.dart` per Flutter coding standards
/// §1 (screen ≤300 lines).
class EventFormPhotoSection extends StatefulWidget {
  const EventFormPhotoSection({
    super.key,
    required this.existingPhotos,
    required this.selectedPhotos,
    required this.onSelectionChanged,
    required this.baseUrl,
    this.uploading = false,
  });

  /// Photos already attached to the event (edit mode only). Empty on
  /// create mode.
  final List<EventPhoto> existingPhotos;

  /// Newly-picked local files not yet uploaded.
  final List<XFile> selectedPhotos;

  /// Called whenever the user adds or removes a locally-picked photo.
  /// The parent owns the upload lifecycle and reads the final list at
  /// submit time.
  final ValueChanged<List<XFile>> onSelectionChanged;

  /// Backend base URL used to resolve existing photo thumbnails. On web
  /// this may be empty (same-origin relative URLs).
  final String baseUrl;

  /// When true, the add button is disabled and an upload spinner is
  /// shown. The parent sets this while uploading after submit.
  final bool uploading;

  @override
  State<EventFormPhotoSection> createState() => _EventFormPhotoSectionState();
}

class _EventFormPhotoSectionState extends State<EventFormPhotoSection> {
  final _picker = ImagePicker();

  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    widget.onSelectionChanged([...widget.selectedPhotos, ...files]);
  }

  void _removeSelected(int index) {
    final next = [...widget.selectedPhotos]..removeAt(index);
    widget.onSelectionChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newCount = widget.selectedPhotos.length;
    final totalCount = widget.existingPhotos.length + newCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(VN.eventPhotos, style: theme.textTheme.titleSmall),
        ),
        if (totalCount == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              VN.noOrderPhotos,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: totalCount,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index < widget.existingPhotos.length) {
                  final photo = widget.existingPhotos[index];
                  return _ExistingPhotoThumb(
                    photo: photo,
                    baseUrl: widget.baseUrl,
                  );
                }
                final newIdx = index - widget.existingPhotos.length;
                return _NewPhotoThumb(
                  file: widget.selectedPhotos[newIdx],
                  onRemove: () => _removeSelected(newIdx),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: widget.uploading ? null : _pickPhotos,
              icon: const Icon(Icons.add_a_photo, size: 18),
              label: const Text(VN.addEventPhoto),
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
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ExistingPhotoThumb extends StatelessWidget {
  const _ExistingPhotoThumb({required this.photo, required this.baseUrl});

  final EventPhoto photo;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        '$baseUrl/api/photos/${photo.photoHash}.jpg',
        width: 70,
        height: 70,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 70,
          height: 70,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image, size: 20),
        ),
      ),
    );
  }
}

class _NewPhotoThumb extends StatelessWidget {
  const _NewPhotoThumb({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(file.path),
            width: 70,
            height: 70,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}