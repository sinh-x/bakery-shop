import 'package:flutter/material.dart';

/// Shared section title text widget used across dashboard and Today Sales
/// screens. Renders [title] in `titleMedium` with bold weight.
///
/// Extracted from the duplicate private `_SectionTitle` classes that were
/// copy-pasted across four files (DG-374 Phase 5.6-c1-fix / CQ-2).
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
