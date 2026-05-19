import 'package:flutter/material.dart';

import '../utils/category_grouping.dart';
import 'package:bakery_app/shared/labels/shared.dart';

class CategorySectionExpansionController {
  final Map<String, bool> _expandedByKey = <String, bool>{};

  bool isExpanded(String key) => _expandedByKey[key] ?? false;

  void setExpanded(String key, bool expanded) {
    _expandedByKey[key] = expanded;
  }
}

class CollapsibleCategorySections<T> extends StatefulWidget {
  const CollapsibleCategorySections({
    super.key,
    required this.sections,
    required this.itemBuilder,
    this.expansionController,
    this.emptyState,
    this.sectionContentBuilder,
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 12),
  });

  final List<GroupedCategorySection<T>> sections;
  final Widget Function(BuildContext context, T item) itemBuilder;
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
  State<CollapsibleCategorySections<T>> createState() =>
      _CollapsibleCategorySectionsState<T>();
}

class _CollapsibleCategorySectionsState<T>
    extends State<CollapsibleCategorySections<T>> {
  late final CategorySectionExpansionController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.expansionController ?? CategorySectionExpansionController();
  }

  @override
  Widget build(BuildContext context) {
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
                    setState(() {
                      _controller.setExpanded(section.categoryKey, !expanded);
                    });
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
                            widget.itemBuilder(context, item),
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
                VN.categorySectionCount(itemCount),
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
