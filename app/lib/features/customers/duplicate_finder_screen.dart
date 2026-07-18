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
class DuplicateFinderScreen extends ConsumerStatefulWidget {
  const DuplicateFinderScreen({super.key});

  @override
  ConsumerState<DuplicateFinderScreen> createState() =>
      _DuplicateFinderScreenState();
}

class _DuplicateFinderScreenState extends ConsumerState<DuplicateFinderScreen> {
  /// Group key currently in flight (DG-252 review Mn7 — in-flight guard
  /// against double merge taps). `null` when no merge is running.
  String? _mergingKey;

  Future<void> _onMerge(
    DuplicateGroup group,
    DuplicateCustomerEntry keep,
    DuplicateCustomerEntry mergeFrom,
  ) async {
    final choice = await showDialog<MergeChoice>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              DuplicateMergeDialog(keep: keep, mergeFrom: mergeFrom),
        );
    if (choice == null) return;
    setState(() => _mergingKey = group.key);
    try {
      await ref.read(customerServiceProvider).mergeCustomers(
            targetId: choice.keep.id,
            sourceId: choice.mergeFrom.id,
          );
      ref.invalidate(customerListProvider);
      await ref.read(duplicateGroupsProvider.notifier).refresh();
      if (mounted) {
        showTopSnackBar(context, CustomersLabels.duplicateFinderMergeSuccess);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, CustomersLabels.duplicateFinderMergeFailed);
        debugPrint('duplicate_finder merge failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _mergingKey = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(CustomersLabels.duplicateFinderLoadingGroups),
            ],
          ),
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
                merging: _mergingKey == group.key,
                onMerge: (keep, mergeFrom) =>
                    _onMerge(group, keep, mergeFrom),
              );
            },
          );
        },
      ),
    );
  }
}