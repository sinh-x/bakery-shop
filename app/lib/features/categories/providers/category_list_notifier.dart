import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/category.dart';

/// Reorder state for the category list (DG-404 Phase 4.7).
///
/// Owns the locally-reordered active-categories list (`_activeCategories`)
/// previously held as a `setState` field inside `_CategoryListState`. The
/// widget reads [categoryListProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class CategoryListState {
  const CategoryListState({this.activeCategories = const <Category>[]});

  final List<Category> activeCategories;

  CategoryListState copyWith({List<Category>? activeCategories}) {
    return CategoryListState(
      activeCategories: activeCategories ?? this.activeCategories,
    );
  }
}

/// `Notifier` that owns the category-list reorder state (DG-404 Phase
/// 4.7). The widget seeds the active list from its `categories` prop on
/// `initState` / `didUpdateWidget` and applies optimistic reorders via
/// [reorder]; the backend persist call is still driven by the widget.
class CategoryListNotifier extends Notifier<CategoryListState> {
  @override
  CategoryListState build() => const CategoryListState();

  void setActiveCategories(List<Category> categories) =>
      state = state.copyWith(activeCategories: categories);

  void reorder(int oldIndex, int newIndex) {
    final list = List<Category>.from(state.activeCategories);
    var newIdx = newIndex;
    if (newIdx > oldIndex) newIdx -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIdx, item);
    state = state.copyWith(activeCategories: list);
  }
}

/// Provider for the category-list reorder state. The widget reads this
/// and calls the notifier's mutators; no `setState` is required.
final categoryListProvider =
    NotifierProvider<CategoryListNotifier, CategoryListState>(
    CategoryListNotifier.new);
