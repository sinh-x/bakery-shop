import 'package:flutter/material.dart';

import '../../../shared/labels/address_labels.dart';

/// Empty-state view shown when the backend returns no missing-links
/// (AC5). Wrapped in a scrollable so [RefreshIndicator] still works on
/// the empty state.
///
/// Extracted from `missing_links_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class MissingLinksEmptyView extends StatelessWidget {
  const MissingLinksEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      // Keep it scrollable so RefreshIndicator works even when empty.
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 40, color: Colors.grey),
                const SizedBox(height: 8),
                Text(
                  AddressLabels.missingLinksEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}