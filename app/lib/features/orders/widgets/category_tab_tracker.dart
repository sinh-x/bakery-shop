import 'package:flutter/material.dart';

import '../../../data/models/category.dart';

/// Wraps the tab body to track the selected category and report changes via
/// [onCategorySelected], so the caller can persist the filter across picker
/// sessions (DG-214 Phase 3).
class CategoryTabTracker extends StatefulWidget {
  const CategoryTabTracker({
    super.key,
    required this.activeCategories,
    required this.child,
    this.onCategorySelected,
  });

  final List<Category> activeCategories;
  final Widget child;
  final void Function(String? slug)? onCategorySelected;

  @override
  State<CategoryTabTracker> createState() => _CategoryTabTrackerState();
}

class _CategoryTabTrackerState extends State<CategoryTabTracker> {
  TabController? _controller;
  int _lastIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (_controller != controller) {
      _controller?.removeListener(_handleTabChange);
      _controller = controller;
      _lastIndex = controller.index;
      controller.addListener(_handleTabChange);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleTabChange);
    super.dispose();
  }

  void _handleTabChange() {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.indexIsChanging && controller.index != _lastIndex) {
      _lastIndex = controller.index;
      final slug = controller.index < widget.activeCategories.length
          ? widget.activeCategories[controller.index].slug
          : null;
      widget.onCategorySelected?.call(slug);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}