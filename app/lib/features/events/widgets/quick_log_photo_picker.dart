import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../providers/photo_upload_provider.dart';
import 'package:bakery_app/shared/labels/events.dart';
/// Compact photo picker for the quick-log event form (FR6).
///
/// Shows a single "Add photos" button by default; expands to a compact
/// thumbnail strip when photos are selected. Designed to keep the
/// dashboard quick-log form compact (NFR1 — upload happens after event
/// creation).
///
/// The add button is disabled while the shared [PhotoUploadNotifier] is
/// uploading; per-photo progress/error/success is rendered by the parent
/// via [UploadProgressIndicator] (FR5). DG-333 Phase 6 removed the deferred
/// `uploading` param — the disabling state is now derived from the notifier.
///
/// Newly-picked files are reported via [onSelectionChanged]; the parent
/// owns the upload lifecycle and reads the final list at submit time.
class QuickLogPhotoPicker extends ConsumerStatefulWidget {
  const QuickLogPhotoPicker({
    super.key,
    required this.selectedPhotos,
    required this.onSelectionChanged,
  });

  /// Newly-picked local files not yet uploaded.
  final List<XFile> selectedPhotos;

  /// Called whenever the user adds or removes a locally-picked photo.
  final ValueChanged<List<XFile>> onSelectionChanged;

  @override
  ConsumerState<QuickLogPhotoPicker> createState() => _QuickLogPhotoPickerState();
}

class _QuickLogPhotoPickerState extends ConsumerState<QuickLogPhotoPicker> {
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
    final count = widget.selectedPhotos.length;
    // Disable the add button while an upload batch is in progress. The
    // per-photo progress/error/success UI is rendered by the parent's
    // UploadProgressIndicator (FR5), so this widget no longer draws its
    // own spinner. DG-333 Phase 6.
    final uploading = ref.watch(photoUploadNotifierProvider).isUploading;
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
        OutlinedButton.icon(
          onPressed: uploading ? null : _pickPhotos,
          icon: const Icon(Icons.add_a_photo, size: 18),
          label: Text(
            count > 0 ? '${EventsLabels.addEventPhoto} ($count)' : EventsLabels.addEventPhoto,
          ),
        ),
      ],
    );
  }
}

class _CompactThumb extends StatefulWidget {
  const _CompactThumb({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  State<_CompactThumb> createState() => _CompactThumbState();
}

class _CompactThumbState extends State<_CompactThumb> {
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
                radius: 28,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              );
            }
            if (!snap.hasData) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: const SizedBox(width: 56, height: 56),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                snap.data!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: widget.onRemove,
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
