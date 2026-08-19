import 'package:bakery_app/shared/utils.dart' show categoryEmojiMap, categoryMap, showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/blank.dart';
import '../../../data/providers/blanks_provider.dart';
import '../../../data/providers/categories_provider.dart';
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

  @override
  void initState() {
    super.initState();
    final b = widget.blank;
    _nameCtrl = TextEditingController(text: b?.name ?? '');
    _unitCtrl = TextEditingController(text: b?.unit ?? '');
    _notesCtrl = TextEditingController(text: b?.notes ?? '');
    // Seed the form notifier with the (optional) Blank being edited.
    Future.microtask(
        () => ref.read(blankFormProvider.notifier).seed(widget.blank));
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
    ref.read(blankFormProvider.notifier).setSaving(true);
    final category = ref.read(blankFormProvider).category;
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
      if (mounted) {
        ref.read(blankFormProvider.notifier).setSaving(false);
        showTopSnackBar(context, e.toString());
      }
    }
  }

  String _categoryLabel(String slug) =>
      '${categoryEmojiMap[slug] ?? ''} ${categoryMap[slug] ?? slug}'.trim();

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final formState = ref.watch(blankFormProvider);
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
                  final active =
                      categories.where((c) => c.active == 1).toList();
                  final validSlugs = active.map((c) => c.slug).toList();
                  final selected = validSlugs.contains(category)
                      ? category
                      : null;
                  return DropdownButtonFormField<String>(
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
                              ref
                                  .read(blankFormProvider.notifier)
                                  .setCategory(v);
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
    final formState = ref.watch(blankFormProvider);
    final category = formState.category;
    final saving = formState.saving;
    final selected =
        categoryMap.containsKey(category) ? category : null;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: BlanksLabels.fieldCategory,
        border: OutlineInputBorder(),
        hintText: BlanksLabels.fieldCategoryHint,
      ),
      items: categoryMap.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(_categoryLabel(e.key))))
          .toList(),
      onChanged: saving
          ? null
          : (v) {
              if (v != null) {
                ref.read(blankFormProvider.notifier).setCategory(v);
              }
            },
    );
  }
}