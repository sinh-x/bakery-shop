import 'package:flutter/material.dart';

import '../../../data/models/address.dart';
import '../../../shared/labels/address_labels.dart';

/// One row of the missing-links list (FR1/FR2/AC1/AC2).
///
/// Renders the [MissingLinkItem.deliveryAddress] as the title and the
/// order count as the subtitle. A trailing "Open in Google Maps" icon
/// button launches Google Maps with the address as the search query via
/// [launchExternalUrl].
///
/// Extracted from `missing_links_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class MissingLinkRow extends StatelessWidget {
  const MissingLinkRow({super.key, required this.item, required this.onOpenMap});

  final MissingLinkItem item;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: const Icon(Icons.location_off_outlined),
      title: Text(item.deliveryAddress),
      subtitle: Text(
        '${item.orderCount}${AddressLabels.missingLinksOrderCountSuffix}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: AddressLabels.missingLinksOpenMapTooltip,
        color: theme.colorScheme.primary,
        onPressed: onOpenMap,
      ),
    );
  }
}