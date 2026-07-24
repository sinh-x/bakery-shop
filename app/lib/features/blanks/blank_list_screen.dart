import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blanks_provider.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/blank_form.dart';
import 'widgets/blank_tile.dart';

/// Blanks management list screen (FR1 / AC1).
///
/// Shows all blanks with a category chip filter bar, a FAB to create a new
/// blank, and pull-to-refresh. Tapping a row navigates to the detail screen.
/// Loading, empty, and error states are rendered inline.
class BlankListScreen extends ConsumerStatefulWidget {
  const BlankListScreen({super.key});

  @override
  ConsumerState<BlankListScreen> createState() => _BlankListScreenState();
}

class _BlankListScreenState extends ConsumerState<BlankListScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  String _selectedCategory = '';

  @override
  String screenRoutePath() => '/blanks';

  @override
  void invalidateProviders() => ref.invalidate(blanksProvider);

  @override
  void initState() {
    super.initState();
    initAutoRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    super.dispose();
  }

  Future<void> _onRefresh() =>
      ref.read(blanksProvider.notifier).refresh();

  void _onCategorySelected(String category) {
    setState(() => _selectedCategory = category);
    ref.read(blanksProvider.notifier).filterByCategory(category);
  }

  List<String> _uniqueCategories(List<Blank> blanks) {
    final set = blanks
        .map((b) => b.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return set;
  }

  @override
  Widget build(BuildContext context) {
    final blanksAsync = ref.watch(blanksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenManage),
        actions: const [AppBarOverflowMenu()],
      ),
      body: blanksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _BlankErrorView(onRetry: _onRefresh),
        data: (blanks) {
          if (blanks.isEmpty) {
            return const _BlankEmptyView();
          }
          return Column(
            children: [
              BlankCategoryFilterBar(
                categories: _uniqueCategories(blanks),
                selected: _selectedCategory,
                onSelected: _onCategorySelected,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: blanks.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        BlankTile(blank: blanks[index]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: BlanksLabels.actionAddBlank,
        onPressed: () => showBlankForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _BlankEmptyView extends StatelessWidget {
  const _BlankEmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            BlanksLabels.emptyBlanks,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _BlankErrorView extends StatelessWidget {
  const _BlankErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(VN.apiError, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(VN.retry),
          ),
        ],
      ),
    );
  }
}