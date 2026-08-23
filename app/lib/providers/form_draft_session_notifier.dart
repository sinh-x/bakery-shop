import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models/form_draft_context.dart';

typedef FormDraftRegistry = Map<FormDraftContext, Object>;

class _FormDraftSessionEpochNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void advance() => state++;
}

final _formDraftSessionEpochStateProvider =
    NotifierProvider<_FormDraftSessionEpochNotifier, int>(
      _FormDraftSessionEpochNotifier.new,
    );

/// Changes whenever the authenticated draft session is cleared.
///
/// Long-lived form families can listen to this provider to reset live state
/// even when the draft registry was already empty at the session boundary.
final formDraftSessionEpochProvider = Provider<int>(
  (ref) => ref.watch(_formDraftSessionEpochStateProvider),
);

/// In-memory drafts retained for the current authenticated app session.
class FormDraftSessionNotifier extends Notifier<FormDraftRegistry> {
  @override
  FormDraftRegistry build() => const <FormDraftContext, Object>{};

  T? readDraft<T extends Object>(FormDraftContext context) {
    final draft = state[context];
    return draft == null ? null : draft as T;
  }

  void retainDraft<T extends Object>(FormDraftContext context, T draft) {
    state = UnmodifiableMapView<FormDraftContext, Object>(
      <FormDraftContext, Object>{...state, context: draft},
    );
  }

  void clearDraft(FormDraftContext context) {
    if (!state.containsKey(context)) return;
    state = UnmodifiableMapView<FormDraftContext, Object>(
      <FormDraftContext, Object>{...state}..remove(context),
    );
  }

  /// Clears [context] only while its retained value still matches [expected].
  ///
  /// Async operations should use this instead of [clearDraft] so completion
  /// cannot remove a newer, unequal replacement draft.
  bool clearDraftIfUnchanged<T extends Object>(
    FormDraftContext context,
    T expected,
  ) {
    final current = state[context];
    if (current == null ||
        (!identical(current, expected) && current != expected)) {
      return false;
    }
    clearDraft(context);
    return true;
  }

  void clearAll() {
    ref.read(_formDraftSessionEpochStateProvider.notifier).advance();
    if (state.isNotEmpty) state = const <FormDraftContext, Object>{};
  }
}

final formDraftSessionProvider =
    NotifierProvider<FormDraftSessionNotifier, FormDraftRegistry>(
      FormDraftSessionNotifier.new,
    );
