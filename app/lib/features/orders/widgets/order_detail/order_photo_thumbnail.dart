import 'package:flutter/material.dart';

import '../order_photo_section.dart';

/// Parses a comma-separated tag string into a set of trimmed, non-empty keys.
/// Mirrors the private `_parseTags` in [OrderPhotoSection] — kept local to
/// avoid widening the API of the exempt `order_photo_section.dart` file.
Set<String> _parseTags(String tags) {
  if (tags.isEmpty) return {};
  return tags
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toSet();
}

/// Renders a single order photo thumbnail with tag chips below it, matching
/// the pattern used by [OrderPhotoSection]. Extracted as a shared widget so
/// the Transactions tab (DG-364 Phase 4.2) can reuse the same thumbnail +
/// tag chip rendering without duplicating ~50 lines.
///
/// The thumbnail is a fixed [width] x [width] square. Tag chips are rendered
/// from [tags] (comma-separated) using [kOrderPhotoTags] for color/label
/// resolution; any unknown key falls back to a grey chip with the raw key as
/// its label.
class OrderPhotoThumbnail extends StatelessWidget {
  const OrderPhotoThumbnail({
    super.key,
    required this.url,
    required this.tags,
    this.width = 90,
    this.onTap,
  });

  /// Full photo URL (e.g. `$baseUrl/api/photos/<hash>.jpg`).
  final String url;

  /// Comma-separated tag string (as stored on [OrderPhoto.tags]).
  final String tags;

  /// Thumbnail edge length in dp.
  final double width;

  /// Optional tap handler (e.g. open full-screen viewer).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagKeys = _parseTags(tags);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: width,
                height: width,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: width,
                  height: width,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
            if (tagKeys.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: tagKeys.map((key) {
                  final tagDef = kOrderPhotoTags
                      .where((t) => t.key == key)
                      .firstOrNull;
                  final color = tagDef?.color ?? Colors.grey;
                  final label = tagDef?.label ?? key;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: color.withAlpha(100),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 8,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}