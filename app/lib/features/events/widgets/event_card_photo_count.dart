import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/event_service.dart' show eventServiceProvider;

/// Photo count indicator badge for event history cards (FR8).
///
/// Lazy-loads the photo count for a single event via
/// [EventService.getEventPhotos] on first build (NFR3 — no N+1
/// explosion; each card fetches its own photos once). Renders nothing
/// when the event has no photos, and a compact "📷 N" badge otherwise.
class EventCardPhotoCount extends ConsumerStatefulWidget {
  const EventCardPhotoCount({super.key, required this.eventId});

  final int eventId;

  @override
  ConsumerState<EventCardPhotoCount> createState() =>
      _EventCardPhotoCountState();
}

class _EventCardPhotoCountState extends ConsumerState<EventCardPhotoCount> {
  int _count = 0;
  bool _loaded = false;
  int? _lastFetchedEventId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCount());
  }

  @override
  void didUpdateWidget(covariant EventCardPhotoCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) {
      _loadCount();
    }
  }

  Future<void> _loadCount() async {
    final eventId = widget.eventId;
    if (eventId <= 0) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    if (_lastFetchedEventId == eventId && _loaded) return;
    try {
      final service = ref.read(eventServiceProvider);
      final photos = await service.getEventPhotos(eventId);
      if (mounted) {
        setState(() {
          _count = photos.length;
          _loaded = true;
          _lastFetchedEventId = eventId;
        });
      }
    } catch (e) {
      debugPrint('EventCardPhotoCount._loadCount failed: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _count == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_camera,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 3),
          Text(
            '$_count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
