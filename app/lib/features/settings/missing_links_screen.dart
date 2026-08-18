import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/address.dart';
import '../../../data/providers/missing_links_provider.dart';
import '../../../shared/labels/address_labels.dart';
import '../../../shared/utils/launch_external_url.dart';

/// Missing-links screen (DG-388 Phase 3 / FR1/FR2/FR6/AC1/AC2/AC5).
///
/// A full-screen read-only list of door-delivery addresses that lack a
/// Google Maps link, backed by `GET /api/addresses/missing-links`
/// (DG-387). Each row shows the raw [MissingLinkItem.deliveryAddress]
/// and its [MissingLinkItem.orderCount], and offers an "Open in Google
/// Maps" button that launches Google Maps with the address text as the
/// search query (FR2/AC2) via [launchExternalUrl]. Pull-to-refresh
/// re-fetches the list (FR6), and empty / error states are shown when
/// appropriate (AC5).
///
/// The list is rendered with `ListView.builder` for lazy rendering up to
/// the backend default limit of 100 items (NFR2). Per the VN Label
/// Policy (NFR3) all user-facing copy lives in [AddressLabels] — no
/// inline Vietnamese strings.
///
/// The screen is reachable from Settings (Phase 5 wires the nav entry)
/// and from the Address Library screen. It is read-only by design: the
/// "Open in Google Maps" button helps staff fill in missing links out
/// of band; in-place editing is out of scope (§5).
class MissingLinksScreen extends ConsumerWidget {
  const MissingLinksScreen({super.key});

  /// Build the Google Maps search URL for [address] (FR2/AC2). Uses the
  /// official `https://www.google.com/maps/search/?api=1&query=...` scheme
  /// so the URL launcher routes to the Google Maps app on mobile and the
  /// web maps site on desktop, with the address text as the search query.
  static String googleMapsSearchUrl(String address) {
    final encoded = Uri.encodeQueryComponent(address.trim());
    return 'https://www.google.com/maps/search/?api=1&query=$encoded';
  }

  Future<void> _openMap(BuildContext context, MissingLinkItem item) async {
    await launchExternalUrl(context, googleMapsSearchUrl(item.deliveryAddress));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync = ref.watch(missingLinksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AddressLabels.missingLinksTitle),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(missingLinksProvider.notifier).refresh(),
        child: linksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _MissingLinksErrorView(error: e),
          data: (items) => items.isEmpty
              ? const _MissingLinksEmptyView()
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return _MissingLinkRow(
                      item: item,
                      onOpenMap: () => _openMap(context, item),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// One row of the missing-links list (FR1/FR2/AC1/AC2).
///
/// Renders the [MissingLinkItem.deliveryAddress] as the title and the
/// order count as the subtitle. A trailing "Open in Google Maps" icon
/// button launches Google Maps with the address as the search query via
/// [launchExternalUrl].
class _MissingLinkRow extends StatelessWidget {
  const _MissingLinkRow({required this.item, required this.onOpenMap});

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

/// Empty-state view shown when the backend returns no missing-links
/// (AC5). Wrapped in a scrollable so [RefreshIndicator] still works on
/// the empty state.
class _MissingLinksEmptyView extends StatelessWidget {
  const _MissingLinksEmptyView();

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

/// Error view for the missing-links screen (AC5). Offers a retry button
/// that re-fetches the list. Wrapped in a scrollable so
/// [RefreshIndicator] still works on the error state.
class _MissingLinksErrorView extends ConsumerWidget {
  const _MissingLinksErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  '${VN.apiError}: $error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(missingLinksProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text(VN.retry),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}