import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

class ChecklistConfigAddState {
  const ChecklistConfigAddState({this.name = ''});

  final String name;
}

class ChecklistConfigAddNotifier extends Notifier<ChecklistConfigAddState> {
  ChecklistConfigAddNotifier(this.context);

  final FormDraftContext context;
  bool _clearingRegistry = false;

  @override
  ChecklistConfigAddState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      state = const ChecklistConfigAddState();
    });
    ref.listen(formDraftSessionProvider, (previous, next) {
      if (!_clearingRegistry &&
          previous?.containsKey(context) == true &&
          !next.containsKey(context)) {
        state = const ChecklistConfigAddState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<ChecklistConfigAddState>(context) ??
        const ChecklistConfigAddState();
  }

  void setName(String value) {
    state = ChecklistConfigAddState(name: value);
    if (value.isEmpty) {
      _clearRegistry();
    } else {
      ref.read(formDraftSessionProvider.notifier).retainDraft(context, state);
    }
  }

  void clear() {
    state = const ChecklistConfigAddState();
    _clearRegistry();
  }

  Object? get retainedDraft => ref.read(formDraftSessionProvider)[context];

  bool completeSuccess(Object? submittedDraft) {
    final drafts = ref.read(formDraftSessionProvider.notifier);
    final currentDraft = ref.read(formDraftSessionProvider)[context];
    final canClear = submittedDraft == null
        ? currentDraft == null
        : drafts.clearDraftIfUnchanged(context, submittedDraft);
    if (canClear) state = const ChecklistConfigAddState();
    return canClear;
  }

  void _clearRegistry() {
    _clearingRegistry = true;
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    _clearingRegistry = false;
  }
}

FormDraftContext checklistConfigAddDraftContext(String period) =>
    FormDraftContext(
      formType: 'checklist-config-add',
      mode: FormDraftMode.create,
      variantId: period,
    );

final checklistConfigAddProvider =
    NotifierProvider.family<
      ChecklistConfigAddNotifier,
      ChecklistConfigAddState,
      FormDraftContext
    >(ChecklistConfigAddNotifier.new);
