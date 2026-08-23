import 'package:bakery_app/shared/utils.dart'
    show categoryEmojiMap, categoryMap, showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/blank.dart';
import '../../../data/providers/blanks_provider.dart';
import '../../../data/providers/categories_provider.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import '../providers/blank_form_notifier.dart';

/// Show the add/edit blank bottom sheet.
///
/// Pass [blank] for edit mode; omit for add mode.
Future<void> showBlankForm(BuildContext context, {Blank? blank}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _BlankForm(blank: blank),
  );
}

class _BlankForm extends ConsumerStatefulWidget {
  const _BlankForm({this.blank});

  final Blank? blank;

  @override
  ConsumerState<_BlankForm> createState() => _BlankFormState();
}

class _BlankFormState extends ConsumerState<_BlankForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _notesCtrl;

  bool get _isEditing => widget.blank != null;
  late final FormDraftContext _draftContext;
  NotifierProvider<BlankFormNotifier, BlankFormState> get _provider =>
      contextualBlankFormProvider(_draftContext);

  @override
  void initState() {
    super.initState();
    final b = widget.blank;
    _draftContext = FormDraftContext(
      formType: 'blank',
      mode: _isEditing ? FormDraftMode.edit : FormDraftMode.create,
      entityId: b?.id.toString(),
    );
    final formNotifier = ref.read(_provider.notifier);
    final draft = formNotifier.newDraft;
    final restore = formNotifier.hasRetainedDraft;
    _nameCtrl = TextEditingController(
      text: restore ? draft.name : b?.name ?? '',
    );
    _unitCtrl = TextEditingController(
      text: restore ? draft.unit : b?.unit ?? '',
    );
    _notesCtrl = TextEditingController(
      text: restore ? draft.notes : b?.notes ?? '',
    );
    _nameCtrl.addListener(_retainNewDraft);
    _unitCtrl.addListener(_retainNewDraft);
    _notesCtrl.addListener(_retainNewDraft);
    // Seed the form notifier with the (optional) Blank being edited.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(_provider.notifier).seed(widget.blank);
    });
  }

  void _retainNewDraft() {
    ref
        .read(_provider.notifier)
        .updateNewDraft(
          name: _nameCtrl.text,
          unit: _unitCtrl.text,
          notes: _notesCtrl.text,
        );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final formNotifier = ref.read(_provider.notifier);
    final submittedDraft = formNotifier.draftSnapshot;
    formNotifier.setSaving(true);
    final category = ref.read(_provider).category;
    try {
      final notifier = ref.read(blanksProvider.notifier);
      if (_isEditing) {
        await notifier.updateBlank(
          widget.blank!.id,
          name: _nameCtrl.text.trim(),
          category: category,
          unit: _unitCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        );
      } else {
        await notifier.createBlank(
          name: _nameCtrl.text.trim(),
          category: category,
          unit: _unitCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        );
      }
      formNotifier.clearAfterSuccess(submittedDraft);
      formNotifier.setSaving(false);
      if (mounted) {
        Navigator.of(context).pop();
        showTopSnackBar(
          context,
          _isEditing
              ? BlanksLabels.messageUpdateSuccess
              : BlanksLabels.messageCreateSuccess,
        );
      }
    } catch (e) {
      formNotifier.setSaving(false);
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    }
  }

  String _categoryLabel(String slug) =>
      '${categoryEmojiMap[slug] ?? ''} ${categoryMap[slug] ?? slug}'.trim();

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final formState = ref.watch(_provider);
    final category = formState.category;
    final saving = formState.saving;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? BlanksLabels.actionEdit
                    : BlanksLabels.screenCreate,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: BlanksLabels.fieldName,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? BlanksLabels.fieldName
                    : null,
              ),
              const SizedBox(height: 12),
              categoriesAsync.when(
                loading: _fallbackCategoryDropdown,
                error: (_, _) => _fallbackCategoryDropdown(),
                data: (categories) {
                  final active = categories
                      .where((c) => c.active == 1)
                      .toList();
                  final validSlugs = active.map((c) => c.slug).toList();
                  final selected = validSlugs.contains(category)
                      ? category
                      : null;
                  return DropdownButtonFormField<String>(
                    key: ValueKey(selected),
                    initialValue: selected,
                    decoration: const InputDecoration(
                      labelText: BlanksLabels.fieldCategory,
                      border: OutlineInputBorder(),
                      hintText: BlanksLabels.fieldCategoryHint,
                    ),
                    items: active
                        .map(
                          (cat) => DropdownMenuItem(
                            value: cat.slug,
                            child: Text(_categoryLabel(cat.slug)),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (v) {
                            if (v != null) {
                              ref.read(_provider.notifier).setCategory(v);
                            }
                          },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitCtrl,
                decoration: const InputDecoration(
                  labelText: BlanksLabels.fieldUnit,
                  border: OutlineInputBorder(),
                ),
              ),
              DiscardFormDraftAction(
                isDirty: ref
                    .watch(formDraftSessionProvider)
                    .containsKey(_draftContext),
                onDiscard: () {
                  ref.read(_provider.notifier).clearNewDraft();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: BlanksLabels.fieldNote,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text(BlanksLabels.actionCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: saving ? null : _save,
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(BlanksLabels.actionSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fallback dropdown used while categories are loading or when the API is
  /// unavailable. Mirrors the product form's hardcoded `categoryMap` /
  /// `categoryEmojiMap` fallback. A stored category that does not match any
  /// fallback slug renders empty (no auto-selection) so the original value is
  /// preserved on save.
  Widget _fallbackCategoryDropdown() {
    final formState = ref.watch(_provider);
    final category = formState.category;
    final saving = formState.saving;
    final selected = categoryMap.containsKey(category) ? category : null;
    return DropdownButtonFormField<String>(
      key: ValueKey(selected),
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: BlanksLabels.fieldCategory,
        border: OutlineInputBorder(),
        hintText: BlanksLabels.fieldCategoryHint,
      ),
      items: categoryMap.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(_categoryLabel(e.key)),
            ),
          )
          .toList(),
      onChanged: saving
          ? null
          : (v) {
              if (v != null) {
                ref.read(_provider.notifier).setCategory(v);
              }
            },
    );
  }
}
