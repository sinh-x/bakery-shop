import 'package:flutter/material.dart';

import 'package:bakery_app/shared/utils.dart' show categoryEmojiMap;
import '../../../data/models/category.dart';

/// Builds the leading icon widget for a category tile.
///
/// Uses the category's [Category.icon] when non-empty, falling back to
/// [categoryEmojiMap] for the category slug, then to a default emoji.
/// When [muted] is true, the icon renders in grey (used for inactive
/// categories).
///
/// Extracted from `category_management_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
Widget buildCategoryIcon(Category category, {bool muted = false}) {
  final emoji = category.icon.isNotEmpty
      ? category.icon
      : (categoryEmojiMap[category.slug] ?? '🎂');
  return Text(
    emoji,
    style: TextStyle(fontSize: 24, color: muted ? Colors.grey : null),
  );
}