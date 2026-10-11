import 'package:flutter/material.dart';

import '../../../data/models/address.dart';
import '../../../shared/labels/address_labels.dart';

/// Presentation for the shared field's grouped suggestions and VN feedback.
/// Focus, query and overlay lifetime remain owned by AddressAutocompleteField.
class AddressAutocompleteOverlay extends StatelessWidget {
  const AddressAutocompleteOverlay({
    super.key,
    required this.response,
    required this.loading,
    required this.hasError,
    required this.onSelected,
  });

  final AddressAutocompleteResponse response;
  final bool loading;
  final bool hasError;
  final ValueChanged<AddressSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(AddressLabels.autocompleteLoading),
          ],
        ),
      );
    }
    if (hasError) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          AddressLabels.autocompleteError,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    final pastOrders = response.pastOrders;
    final library = response.library;
    if (pastOrders.isEmpty && library.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(AddressLabels.autocompleteNoResults),
      );
    }

    // Headers appear only when both groups have results; customer history
    // stays first, preserving the compact single-source presentation.
    final showHeaders = pastOrders.isNotEmpty && library.isNotEmpty;
    final children = <Widget>[];
    if (pastOrders.isNotEmpty) {
      if (showHeaders) {
        children.add(
          const _SectionHeader(AddressLabels.autocompleteSectionPastOrders),
        );
      }
      for (final suggestion in pastOrders) {
        children.add(_suggestionTile(suggestion));
      }
    }
    if (library.isNotEmpty) {
      if (showHeaders) {
        children.add(
          const _SectionHeader(AddressLabels.autocompleteSectionLibrary),
        );
      }
      for (final suggestion in library) {
        children.add(_suggestionTile(suggestion));
      }
    }
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: children,
    );
  }

  Widget _suggestionTile(AddressSuggestion suggestion) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.location_on_outlined, size: 18),
      title: Text(suggestion.displayAddress),
      subtitle: suggestion.isCustomerAddress
          ? const Text(
              AddressLabels.customerAddressBadge,
              style: TextStyle(fontSize: 11),
            )
          : null,
      trailing: suggestion.googleMapsUrl != null
          ? const Icon(Icons.map_outlined, size: 16)
          : null,
      onTap: () => onSelected(suggestion),
    );
  }
}

/// Non-interactive group header, displayed only for mixed-source results.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
