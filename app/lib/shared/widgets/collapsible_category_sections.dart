import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/collapsible_category_sections_notifier.dart';
import '../utils/category_grouping.dart';
import 'package:bakery_app/shared/labels/stock.dart';
class CategorySectionExpansionController {
  final Map<String, bool> _expandedByKey = <String, bool>{};

  bool isExpanded(String key) => _expandedByKey[key] ?? false;

  void setExpanded(String key, bool expanded) {
    _expandedByKey[key] = expanded;
  }
}

class CollapsibleCategorySections<T> extends ConsumerStatefulWidget {
  const CollapsibleCategorySections({
    super.key,
    required this.sections,
    this.itemBuilder,
    this.expansionController,
    this.emptyState,
    this.sectionContentBuilder,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 12),
  }) : assert(
          itemBuilder != null || sectionContentBuilder != null,
          'Provide itemBuilder or sectionContentBuilder',
        );

  final List<GroupedCategorySection<T>> sections;
  final Widget Function(BuildContext context, T item)? itemBuilder;
  final CategorySectionExpansionController? expansionController;
  final Widget? emptyState;
  final Widget Function(
    BuildContext context,
    GroupedCategorySection<T> section,
  )?
  sectionContentBuilder;
  final EdgeInsetsGeometry headerPadding;
  final EdgeInsetsGeometry contentPadding;

  @override
  ConsumerState<CollapsibleCategorySections<T>> createState() =>
      _CollapsibleCategorySectionsState<T>();
}

class _CollapsibleCategorySectionsState<T>
    extends ConsumerState<CollapsibleCategorySections<T>> {
  late final CategorySectionExpansionController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.expansionController ?? CategorySectionExpansionController();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the rebuild tick so the list refreshes after each toggle
    // (DG-404 Phase 4.7). The expansion state itself lives in the
    // (internal or caller-supplied) [CategorySectionExpansionController];
    // the notifier just signals rebuild — replacing the pre-migration
    // empty `setState` closure that wrapped the toggle.
    ref.watch(collapsibleCategorySectionsRebuildProvider);
    if (widget.sections.isEmpty) {
      return widget.emptyState ?? const SizedBox.shrink();
    }

    return ListView.builder(
      itemCount: widget.sections.length,
      itemBuilder: (context, sectionIndex) {
        final section = widget.sections[sectionIndex];
        final expanded = _controller.isExpanded(section.categoryKey);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: widget.headerPadding,
                child: _SectionHeader(
                  categoryName: section.categoryName,
                  itemCount: section.items.length,
                  expanded: expanded,
                  onTap: () {
                    _controller.setExpanded(section.categoryKey, !expanded);
                    ref
                        .read(collapsibleCategorySectionsRebuildProvider
                            .notifier)
                        .bump();
                  },
                ),
              ),
              if (expanded)
                Padding(
                  padding: widget.contentPadding,
                  child:
                      widget.sectionContentBuilder?.call(context, section) ??
                      Column(
                        children: [
                          for (final item in section.items)
                            if (widget.itemBuilder != null)
                              widget.itemBuilder!(context, item),
                        ],
                      ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.categoryName,
    required this.itemCount,
    required this.expanded,
    required this.onTap,
  });

  final String categoryName;
  final int itemCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                StockLabels.categorySectionCount(itemCount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              Icon(expanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }
}
