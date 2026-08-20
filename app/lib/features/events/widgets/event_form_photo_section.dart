import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/event_photo.dart';
import '../../../providers/photo_upload_provider.dart';
import 'package:bakery_app/shared/labels/events.dart';
/// Photo picker + preview section for the event create/edit form.
///
/// Shows existing event photos (fetched via `EventService.getEventPhotos`)
/// alongside newly-picked local files ([XFile]). Newly-picked files are
/// reported to the parent via [onSelectionChanged] for upload after the
/// event is created or updated.
///
/// The add button is disabled while the shared [PhotoUploadNotifier] is
/// uploading; per-photo progress/error/success is rendered by the parent
/// via [UploadProgressIndicator] (FR5). DG-333 Phase 6 removed the deferred
/// `uploading` param — the disabling state is now derived from the notifier.
///
/// Extracted from `event_form_screen.dart` per Flutter coding standards
/// §1 (screen ≤300 lines).
class EventFormPhotoSection extends ConsumerStatefulWidget {
  const EventFormPhotoSection({
    super.key,
    required this.existingPhotos,
    required this.selectedPhotos,
    required this.onSelectionChanged,
    required this.baseUrl,
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

  @override
  ConsumerState<EventFormPhotoSection> createState() =>
      _EventFormPhotoSectionState();
}

class _EventFormPhotoSectionState extends ConsumerState<EventFormPhotoSection> {
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
    // Disable the add button while an upload batch is in progress. The
    // per-photo progress/error/success UI is rendered by the parent's
    // UploadProgressIndicator (FR5), so this widget no longer draws its
    // own spinner. DG-333 Phase 6.
    final uploading = ref.watch(photoUploadNotifierProvider).isUploading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(EventsLabels.eventPhotos, style: theme.textTheme.titleSmall),
        ),
        if (totalCount == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              EventsLabels.noEventPhotos,
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
        OutlinedButton.icon(
          onPressed: uploading ? null : _pickPhotos,
          icon: const Icon(Icons.add_a_photo, size: 18),
          label: const Text(EventsLabels.addEventPhoto),
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

class _NewPhotoThumb extends StatefulWidget {
  const _NewPhotoThumb({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  State<_NewPhotoThumb> createState() => _NewPhotoThumbState();
}

class _NewPhotoThumbState extends State<_NewPhotoThumb> {
  late final Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.file.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FutureBuilder<Uint8List>(
          future: _bytesFuture,
          builder: (context, snap) {
            if (snap.hasError) {
              return CircleAvatar(
                radius: 35,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.outline,
                ),
              );
            }
            if (!snap.hasData) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const SizedBox(width: 70, height: 70),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snap.data!,
                width: 70,
                height: 70,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
        Positioned(
          top: -8,
          right: -8,
          child: GestureDetector(
            onTap: widget.onRemove,
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
