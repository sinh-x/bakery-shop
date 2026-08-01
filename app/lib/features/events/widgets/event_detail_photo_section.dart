import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart' show apiBaseUrlProvider;
import '../../../data/models/event_photo.dart';
import 'event_photo_viewer.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Read-only photo gallery for the event detail screen.
///
/// Fetches nothing itself — the parent screen owns the load lifecycle
/// and passes the resolved [photos], [loading], and [error] state.
/// Renders a horizontal thumbnail strip that opens [EventPhotoViewer]
/// on tap. Extracted from `event_detail_screen.dart` per Flutter coding
/// standards §1 (screen ≤300 lines).
class EventDetailPhotoSection extends ConsumerWidget {
  const EventDetailPhotoSection({
    super.key,
    required this.photos,
    required this.loading,
    this.error,
  });

  final List<EventPhoto> photos;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (loading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '${VN.apiError}: $error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }
    if (photos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          VN.noEventPhotos,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    final baseUrl = ref.read(apiBaseUrlProvider);
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final photo = photos[index];
          final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
          return GestureDetector(
            onTap: () => _openViewer(context, ref, index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 100,
                  height: 100,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openViewer(BuildContext context, WidgetRef ref, int index) {
    final baseUrl = ref.read(apiBaseUrlProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventPhotoViewer(
          photos: photos,
          initialIndex: index,
          baseUrl: baseUrl,
        ),
      ),
    );
  }
}
