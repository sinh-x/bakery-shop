import 'package:flutter/material.dart';

/// Small rounded badge displaying a category's code prefix.
///
/// When [muted] is true, the badge renders in grey tones (used for
/// inactive categories).
///
/// Extracted from `category_management_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CodePrefixBadge extends StatelessWidget {
  const CodePrefixBadge({super.key, required this.codePrefix, this.muted = false});

  final String codePrefix;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? Colors.grey.shade200 : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        codePrefix,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: muted ? Colors.grey : colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}