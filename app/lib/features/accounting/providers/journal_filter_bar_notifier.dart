import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Journal-tab filter state (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_since`, `_until`, `_accountId`, and `_sourceType` filter
/// fields previously mutated via `setState` inside `_JournalTabState`. The
/// widget reads [journalFilterBarProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class JournalFilterBarState {
  const JournalFilterBarState({
    this.since,
    this.until,
    this.accountId,
    this.sourceType,
  });

  final String? since;
  final String? until;
  final int? accountId;
  final String? sourceType;

  JournalFilterBarState copyWith({
    String? since,
    String? until,
    int? accountId,
    String? sourceType,
  }) =>
      JournalFilterBarState(
        since: since ?? this.since,
        until: until ?? this.until,
        accountId: accountId ?? this.accountId,
        sourceType: sourceType ?? this.sourceType,
      );
}

class JournalFilterBarNotifier extends Notifier<JournalFilterBarState> {
  @override
  JournalFilterBarState build() => const JournalFilterBarState();

  void setSince(String? value) => state = state.copyWith(since: value);

  void setUntil(String? value) => state = state.copyWith(until: value);

  void setAccountId(int? value) => state = state.copyWith(accountId: value);

  void setSourceType(String? value) =>
      state = state.copyWith(sourceType: value);
}

final journalFilterBarProvider =
    NotifierProvider<JournalFilterBarNotifier, JournalFilterBarState>(
        JournalFilterBarNotifier.new);