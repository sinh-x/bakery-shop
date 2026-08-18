import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/customers.dart';

import '../../../data/providers/customers_provider.dart';
import 'customer_tile.dart';
import 'load_more_tile.dart';

/// Paginated customer list with infinite-scroll load-more and pull-to-refresh.
///
/// Renders an empty state when [state.loaded] is empty, otherwise a
/// [ListView.separated] whose last item is a [LoadMoreTile] footer.
///
/// Extracted from `customer_list_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CustomerList extends StatelessWidget {
  const CustomerList({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final CustomerPaginationState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final customers = state.loaded;
    if (customers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(CustomersLabels.noCustomers),
          ],
        ),
      );
    }

    // DG-409 Phase 4: infinite-scroll via a scroll listener that triggers
    // load-more near the bottom. Combined with the explicit "Tải thêm"
    // affordance below for discoverability.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200 &&
            state.hasMore &&
            !state.isLoadingMore) {
          onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          itemCount: customers.length + 1,
          itemBuilder: (context, index) {
            if (index == customers.length) {
              return LoadMoreTile(
                state: state,
                onLoadMore: onLoadMore,
              );
            }
            return CustomerTile(customer: customers[index]);
          },
          separatorBuilder: (_, _) => const Divider(height: 1),
        ),
      ),
    );
  }
}