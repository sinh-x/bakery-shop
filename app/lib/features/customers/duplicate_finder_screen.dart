import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/customer_service.dart';
import '../../providers/customers_provider.dart';
import '../../shared/labels/customers.dart';
import 'widgets/duplicate_group_tile.dart';
import 'widgets/duplicate_merge_dialog.dart';

/// Admin-only duplicate-finder + merge screen (DG-252 Phase 7 — FR7/AC4).
///
/// Lists duplicate candidate groups returned by `GET /api/customers/duplicates`
/// (admin-only on the backend). Each group offers a merge action that opens
/// [DuplicateMergeDialog] showing both records' order counts; confirming
/// calls `POST /api/customers/{id}/merge` and refreshes the list.
///
/// Route-gated by the router redirect guard via `_adminOnlyRoutes`
/// (`app_router.dart`). Staff users hitting `/customers/duplicates` are
/// redirected to the admin-access-denied page.
class DuplicateFinderScreen extends ConsumerWidget {
  const DuplicateFinderScreen({super.key});

  Future<void> _onMerge(
    BuildContext context,
    WidgetRef ref,
    DuplicateCustomerEntry keep,
    DuplicateCustomerEntry mergeFrom,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => DuplicateMergeDialog(keep: keep, mergeFrom: mergeFrom),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(customerServiceProvider).mergeCustomers(
            targetId: keep.id,
            sourceId: mergeFrom.id,
          );
      ref.invalidate(customerListProvider);
      await ref.read(duplicateGroupsProvider.notifier).refresh();
      if (context.mounted) {
        showTopSnackBar(context, CustomersLabels.duplicateFinderMergeSuccess);
      }
    } catch (e) {
      if (context.mounted) {
        showTopSnackBar(context, CustomersLabels.duplicateFinderMergeFailed);
        debugPrint('duplicate_finder merge failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(duplicateGroupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(CustomersLabels.duplicateFinderTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: CustomersLabels.duplicateFinderRefresh,
            onPressed: () =>
                ref.read(duplicateGroupsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(VN.apiError),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(duplicateGroupsProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text(CustomersLabels.duplicateFinderRetry),
              ),
            ],
          ),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(CustomersLabels.duplicateFinderEmpty),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return DuplicateGroupTile(
                group: group,
                merging: false,
                onMerge: (keep, mergeFrom) =>
                    _onMerge(context, ref, keep, mergeFrom),
              );
            },
          );
        },
      ),
    );
  }
}