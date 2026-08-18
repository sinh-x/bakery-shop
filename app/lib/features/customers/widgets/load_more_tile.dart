import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/shared.dart';

import '../../../data/providers/customers_provider.dart';

/// Footer tile rendered at the end of the customer list. Shows a loading
/// spinner while fetching the next page, a "Tải thêm" button when more pages
/// remain, or nothing when all customers are loaded (DG-409 Phase 4).
///
/// Extracted from `customer_list_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class LoadMoreTile extends StatelessWidget {
  const LoadMoreTile({
    super.key,
    required this.state,
    required this.onLoadMore,
  });

  final CustomerPaginationState state;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!state.hasMore && !state.isLoadingMore) {
      return const SizedBox.shrink();
    }
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: Text(
            '${SharedLabels.loadMore} (${state.total - state.loaded.length})',
          ),
        ),
      ),
    );
  }
}