import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the knowledge list screen filter (DG-404 Phase 4.7 / FR2).
///
/// Owns the selected type filter previously held as a `setState` field
/// inside `_KnowledgeListScreenState`. The search query is owned by the
/// widget's `TextEditingController` (acceptable-use) and read back from
/// it for local filtering; the notifier only owns the type filter.
class KnowledgeListFilterState {
  const KnowledgeListFilterState({this.selectedType});

  final String? selectedType;

  KnowledgeListFilterState copyWith({String? selectedType}) {
    return KnowledgeListFilterState(
      selectedType: selectedType ?? this.selectedType,
    );
  }
}

/// `Notifier` that owns the knowledge-list filter state (DG-404 Phase
/// 4.7 / FR2). The widget reads [knowledgeListFilterProvider] and
/// invokes mutators; no `setState` is required.
class KnowledgeListFilterNotifier
    extends Notifier<KnowledgeListFilterState> {
  @override
  KnowledgeListFilterState build() => const KnowledgeListFilterState();

  void seed(String? initialType) =>
      state = KnowledgeListFilterState(selectedType: initialType);

  void setSelectedType(String? type) =>
      state = state.copyWith(selectedType: type);
}

/// Provider for the knowledge-list filter state.
final knowledgeListFilterProvider =
    NotifierProvider<KnowledgeListFilterNotifier, KnowledgeListFilterState>(
        KnowledgeListFilterNotifier.new);