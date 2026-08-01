import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart' show apiBaseUrlProvider;
import '../../../data/api/event_service.dart' show eventServiceProvider;
import '../../../data/models/event_photo.dart';
import '../../events/widgets/event_photo_viewer.dart';

/// Compact horizontal photo thumbnail strip for the expense history card.
///
/// Lazy-loads photos for a single event via [EventService.getEventPhotos]
/// on first build (NFR3 — no N+1 explosion; each card fetches its own
/// photos once). Tapping a thumbnail opens the full-screen
/// [EventPhotoViewer].
///
/// Extracted from `expense_history_card.dart` per Flutter coding standards
/// §1 (widget ≤200 lines).
class ExpenseHistoryPhotoStrip extends ConsumerStatefulWidget {
  const ExpenseHistoryPhotoStrip({super.key, required this.eventId});

  final int eventId;

  @override
  ConsumerState<ExpenseHistoryPhotoStrip> createState() =>
      _ExpenseHistoryPhotoStripState();
}

class _ExpenseHistoryPhotoStripState
    extends ConsumerState<ExpenseHistoryPhotoStrip> {
  List<EventPhoto> _photos = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final service = ref.read(eventServiceProvider);
      final photos = await service.getEventPhotos(widget.eventId);
      if (mounted) {
        setState(() {
          _photos = photos;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ExpenseHistoryPhotoStrip._loadPhotos failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 72,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_photos.isEmpty) return const SizedBox.shrink();
    final baseUrl = ref.read(apiBaseUrlProvider);
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final photo = _photos[index];
          final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
          return GestureDetector(
            onTap: () => _openViewer(context, baseUrl, index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                url,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 64,
                  height: 64,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image, size: 18),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openViewer(BuildContext context, String baseUrl, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventPhotoViewer(
          photos: _photos,
          initialIndex: index,
          baseUrl: baseUrl,
        ),
      ),
    );
  }
}
