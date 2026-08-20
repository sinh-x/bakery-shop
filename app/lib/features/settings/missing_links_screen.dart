import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/address.dart';
import '../../../data/providers/missing_links_provider.dart';
import '../../../shared/labels/address_labels.dart';
import '../../../shared/utils/launch_external_url.dart';
import 'widgets/missing_link_row.dart';
import 'widgets/missing_links_empty_view.dart';
import 'widgets/missing_links_error_view.dart';
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
          error: (e, _) => MissingLinksErrorView(error: e),
          data: (items) => items.isEmpty
              ? const MissingLinksEmptyView()
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return MissingLinkRow(
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