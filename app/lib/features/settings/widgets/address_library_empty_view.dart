import 'package:flutter/material.dart';

import '../../../shared/labels/address_labels.dart';

/// Empty-state view shown when the library has no entries (or no
/// matches for the current search). Distinguishes "no entries" from
/// "no matches" via [hasSearch] so the user knows whether to clear the
/// search or add a new entry.
///
/// Extracted from `address_library_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class AddressLibraryEmptyView extends StatelessWidget {
  const AddressLibraryEmptyView({super.key, required this.hasSearch});

  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? AddressLabels.libraryNoMatches
                  : AddressLabels.libraryEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}