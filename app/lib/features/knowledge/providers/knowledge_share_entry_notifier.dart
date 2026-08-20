import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the knowledge-detail share-entry button (DG-404 Phase 4.7 /
/// FR2).
///
/// Owns the sharing flag previously held as a `setState` field inside
/// `_ShareEntryButtonState`.
class KnowledgeShareEntryState {
  const KnowledgeShareEntryState({this.sharing = false});

  final bool sharing;

  KnowledgeShareEntryState copyWith({bool? sharing}) {
    return KnowledgeShareEntryState(sharing: sharing ?? this.sharing);
  }
}

/// `Notifier` that owns the share-entry button state (DG-404 Phase 4.7 /
/// FR2). The widget reads [knowledgeShareEntryProvider] and invokes
/// mutators; no `setState` is required.
class KnowledgeShareEntryNotifier
    extends Notifier<KnowledgeShareEntryState> {
  @override
  KnowledgeShareEntryState build() => const KnowledgeShareEntryState();

  void setSharing(bool value) => state = state.copyWith(sharing: value);
}

/// Provider for the share-entry button state.
final knowledgeShareEntryProvider =
    NotifierProvider<KnowledgeShareEntryNotifier, KnowledgeShareEntryState>(
        KnowledgeShareEntryNotifier.new);