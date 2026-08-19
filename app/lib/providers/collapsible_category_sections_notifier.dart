import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rebuild trigger for [CollapsibleCategorySections] (DG-404 Phase
/// 4.7 / FR2). The widget previously issued an empty
/// `setState(() { _controller.setExpanded(key, !expanded); })` to
/// toggle a category section's expansion and rebuild the list. The
/// expansion state itself lives in the (internal or caller-supplied)
/// [CategorySectionExpansionController]; this notifier replaces the
/// empty `setState` with a counter bump the widget watches so the
/// list rebuilds after each toggle. Keeping the expansion state out
/// of Riverpod preserves the existing public contract where callers
/// may supply their own controller (e.g. stock/pos screens).
class CollapsibleCategorySectionsRebuildNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Bump the rebuild counter so the widget re-reads the
  /// controller-backed expansion state. Replaces the pre-migration
  /// empty `setState` closure that wrapped the toggle.
  void bump() => state++;
}

/// Provider for the collapsible-category-sections rebuild trigger.
final collapsibleCategorySectionsRebuildProvider =
    NotifierProvider<CollapsibleCategorySectionsRebuildNotifier, int>(
        CollapsibleCategorySectionsRebuildNotifier.new);