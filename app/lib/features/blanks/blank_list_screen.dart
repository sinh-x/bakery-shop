import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blanks_provider.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'providers/blank_list_filter_notifier.dart';
import 'widgets/blank_form.dart';
import 'widgets/blank_tile.dart';
import 'widgets/blanks_states.dart';

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
    ref.read(blankListFilterProvider.notifier).select(category);
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
    final selectedCategory = ref.watch(blankListFilterProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenManage),
        actions: [
          AppBarOverflowMenu(
            items: const [
              PopupMenuItem<String>(
                value: 'stock',
                child: Row(
                  children: [
                    Icon(Icons.inventory),
                    SizedBox(width: 8),
                    Text(BlanksLabels.screenStock),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'demand',
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined),
                    SizedBox(width: 8),
                    Text(BlanksLabels.screenDemand),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'stock':
                  context.push('/blanks/stock');
                case 'demand':
                  context.push('/blanks/demand');
              }
            },
          ),
        ],
      ),
      body: blanksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => BlanksErrorView(onRetry: _onRefresh),
        data: (blanks) {
          if (blanks.isEmpty) {
            return const BlanksEmptyView(
              icon: Icons.inventory_2_outlined,
              label: BlanksLabels.emptyBlanks,
            );
          }
          return Column(
            children: [
              BlankCategoryFilterBar(
                categories: _uniqueCategories(blanks),
                selected: selectedCategory,
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