import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/customer_service.dart';
import '../../providers/customers_provider.dart';
import '../../shared/labels/customers.dart';
import '../../shared/utils/diacritics.dart';
import 'widgets/duplicate_batch_merge_dialog.dart';
import 'widgets/duplicate_group_tile.dart';
import 'widgets/duplicate_merge_dialog.dart';

/// Returns `true` if any member of [group] matches [query]
/// (case-insensitive, diacritic-insensitive) against `name` or `phone`.
///
/// The group is the atomic display unit: a single matching member shows the
/// entire group (FR3/FR4). Reuses `stripDiacritics` from
/// `shared/utils/diacritics.dart` (extracted in Phase 4.1).
bool _groupMatches(DuplicateGroup group, String query) {
  final q = stripDiacritics(query.trim().toLowerCase());
  if (q.isEmpty) return true;
  for (final m in group.customers) {
    final name = stripDiacritics(m.name.trim().toLowerCase());
    if (name.contains(q)) return true;
    final phone = m.phone.trim().toLowerCase();
    if (phone.contains(q)) return true;
  }
  return false;
}

/// Admin-only duplicate-finder + merge screen (DG-252 Phase 7 — FR7/AC4,
/// extended by DG-369 Phase 3 for batch merge of 3+ members).
///
/// Lists duplicate candidate groups returned by `GET /api/customers/duplicates`
/// (admin-only on the backend). Each group offers a merge action:
/// - **2 selected members** → opens [DuplicateMergeDialog] (single-pair merge
///   with swap affordance) calling `POST /api/customers/{id}/merge`.
/// - **3+ selected members** → opens [DuplicateBatchMergeDialog] (batch
///   confirmation listing primary + all sources) calling
///   `POST /api/customers/{id}/batch-merge`.
///
/// On success the customer list is invalidated and the duplicate groups are
/// refreshed (AC6).
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

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(duplicateFinderSearchProvider.notifier).set(query);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(duplicateFinderSearchProvider.notifier).clear();
  }

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

  Future<void> _onBatchMerge(
    DuplicateGroup group,
    DuplicateCustomerEntry primary,
    List<DuplicateCustomerEntry> sources,
  ) async {
    final choice = await showDialog<BatchMergeChoice>(
          context: context,
          barrierDismissible: false,
          builder: (_) => DuplicateBatchMergeDialog(
            primary: primary,
            sources: sources,
          ),
        );
    if (choice == null) return;
    setState(() => _mergingKey = group.key);
    try {
      await ref.read(customerServiceProvider).batchMergeCustomers(
            targetId: choice.primary.id,
            sourceCustomerIds: choice.sources.map((s) => s.id).toList(),
          );
      ref.invalidate(customerListProvider);
      await ref.read(duplicateGroupsProvider.notifier).refresh();
      if (mounted) {
        showTopSnackBar(
            context, CustomersLabels.duplicateFinderBatchMergeSuccess);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
            context, CustomersLabels.duplicateFinderBatchMergeFailed);
        debugPrint('duplicate_finder batch merge failed: $e');
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
    final search = ref.watch(duplicateFinderSearchProvider);
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: CustomersLabels.duplicateFinderSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                        tooltip: VN.clear,
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: async.when(
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
                        Icon(Icons.check_circle_outline,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(CustomersLabels.duplicateFinderEmpty),
                      ],
                    ),
                  );
                }
                final filtered = search.isEmpty
                    ? groups
                    : groups.where((g) => _groupMatches(g, search)).toList();
                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(CustomersLabels.duplicateFinderSearchNoResults),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final group = filtered[index];
                    return DuplicateGroupTile(
                      group: group,
                      merging: _mergingKey == group.key,
                      onMerge: (keep, mergeFrom) =>
                          _onMerge(group, keep, mergeFrom),
                      onBatchMerge: (primary, sources) =>
                          _onBatchMerge(group, primary, sources),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}