import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart' show apiBaseUrlProvider;
import '../../../data/api/event_service.dart' show eventServiceProvider;
import '../../../data/models/event_photo.dart';
import '../../events/widgets/event_photo_viewer.dart';
import '../providers/expense_history_photo_notifier.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPhotos());
  }

  @override
  void didUpdateWidget(covariant ExpenseHistoryPhotoStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) {
      _loadPhotos();
    }
  }

  Future<void> _loadPhotos() async {
    final eventId = widget.eventId;
    if (eventId <= 0) {
      if (mounted) {
        ref
            .read(expenseHistoryPhotoProvider(eventId).notifier)
            .setLoading(false);
      }
      return;
    }
    final notifier = ref.read(expenseHistoryPhotoProvider(eventId).notifier);
    final state = ref.read(expenseHistoryPhotoProvider(eventId));
    if (state.lastFetchedEventId == eventId && state.photos.isNotEmpty) return;
    try {
      final service = ref.read(eventServiceProvider);
      final photos = await service.getEventPhotos(eventId);
      if (mounted) notifier.setPhotos(photos);
    } catch (e) {
      debugPrint('ExpenseHistoryPhotoStrip._loadPhotos failed: $e');
      if (mounted) notifier.setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(expenseHistoryPhotoProvider(widget.eventId));
    if (state.loading) {
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
    if (state.photos.isEmpty) return const SizedBox.shrink();
    final baseUrl = ref.read(apiBaseUrlProvider);
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: state.photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final photo = state.photos[index];
          final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
          return GestureDetector(
            onTap: () => _openViewer(context, baseUrl, index, state.photos),
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

  void _openViewer(
    BuildContext context,
    String baseUrl,
    int index,
    List<EventPhoto> photos,
  ) {
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