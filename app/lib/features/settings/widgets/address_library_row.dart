import 'package:flutter/material.dart';

import '../../../data/models/address.dart';
import '../../../shared/labels/address_labels.dart';
import '../../../shared/utils/launch_external_url.dart';

/// One row of the address library list (FR6/AC6).
///
/// Renders the address as the title and an optional map-link icon +
/// truncated link as subtitle when [AddressLibraryEntry.googleMapsUrl]
/// is non-null. Edit and delete affordances are exposed via a trailing
/// row of icon buttons. When the entry has a stored Google Maps link,
/// an "Open in Google Maps" shortcut button (DG-388 Phase 5.6-c5 / FB-2)
/// launches the link via [launchExternalUrl], mirroring the
/// missing-links screen pattern.
///
/// Extracted from `address_library_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class AddressLibraryRow extends StatelessWidget {
  const AddressLibraryRow({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final AddressLibraryEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLink = entry.googleMapsUrl != null &&
        entry.googleMapsUrl!.trim().isNotEmpty;
    return ListTile(
      leading: const Icon(Icons.location_on_outlined),
      title: Text(entry.displayAddress),
      subtitle: hasLink
          ? Row(
              children: [
                Icon(Icons.map_outlined,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    entry.googleMapsUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasLink)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: AddressLabels.libraryOpenMapTooltip,
              onPressed: () =>
                  launchExternalUrl(context, entry.googleMapsUrl),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: AddressLabels.libraryEditTooltip,
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: AddressLabels.libraryDeleteTooltip,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}