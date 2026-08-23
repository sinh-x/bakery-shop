import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../providers/form_draft_session_notifier.dart';

/// Order submission re-entry-guard state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_isSubmitting` and `_submitted` fields previously mutated via
/// `setState` inside `OrderSubmissionMixin` (a mixin on `ConsumerState`).
/// The host screen reads [orderSubmissionGuardProvider] and invokes the
/// notifier's mutators; the `setState` calls in the mixin's `submitOrder`
/// spine are replaced by `state =` writes here.
class OrderSubmissionGuardNotifier extends Notifier<bool> {
  OrderSubmissionGuardNotifier(this.context);

  final FormDraftContext context;
  int _generation = 0;

  /// `true` while the shared submission spine is in progress.
  @override
  bool build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      _generation++;
      state = false;
    });
    return false;
  }

  void setSubmitting(bool value) => state = value;

  int start() {
    state = true;
    return ++_generation;
  }

  void finishIfCurrent(int generation) {
    if (generation == _generation) state = false;
  }
}

final orderSubmissionGuardProvider =
    NotifierProvider.family<
      OrderSubmissionGuardNotifier,
      bool,
      FormDraftContext
    >(OrderSubmissionGuardNotifier.new);

/// Post-submit latch read by the host's `_saveDraft` helper so it skips
/// persisting a draft after a successful submission (FR6). Mirrors the
/// `_submitted` field in the mixin.
class OrderSubmissionLatchNotifier extends Notifier<bool> {
  OrderSubmissionLatchNotifier(this.context);

  final FormDraftContext context;
  @override
  bool build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) => state = false);
    return false;
  }

  void setSubmitted() => state = true;

  /// Reset the post-submit latch so the next order's draft-save (FR6) is
  /// not silently skipped. Invoked on new-order entry (create/POS checkout
  /// `initState`) so each order starts with the latch false — the prior
  /// `setState`-backed `_submitted` field was per-screen and reset on
  /// rebuild, but this global `NotifierProvider` is not `autoDispose` and
  /// would otherwise latch `true` permanently after the first submission
  /// (DG-404 review CQ-1).
  void resetSubmitted() => state = false;
}

final orderSubmissionLatchProvider =
    NotifierProvider.family<
      OrderSubmissionLatchNotifier,
      bool,
      FormDraftContext
    >(OrderSubmissionLatchNotifier.new);
