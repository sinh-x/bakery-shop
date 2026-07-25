import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/blank.dart';
import '../../../data/providers/blanks_provider.dart';
import '../../../providers/categories_provider.dart';
import 'package:bakery_app/shared/labels/blanks.dart';

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
  // Category is managed as a slug selected from the server-managed Category
  // dropdown (same source as the product form). Existing blanks whose stored
  // category does not match any server Category slug are preserved: the
  // dropdown renders empty (hint) and the original value is kept on save
  // unless the user picks a new one.
  late String _category;
  bool _saving = false;

  bool get _isEditing => widget.blank != null;

  @override
  void initState() {
    super.initState();
    final b = widget.blank;
    _nameCtrl = TextEditingController(text: b?.name ?? '');
    _category = b?.category ?? '';
    _unitCtrl = TextEditingController(text: b?.unit ?? '');
    _notesCtrl = TextEditingController(text: b?.notes ?? '');
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
    setState(() => _saving = true);
    try {
      final notifier = ref.read(blanksProvider.notifier);
      if (_isEditing) {
        await notifier.updateBlank(
          widget.blank!.id,
          name: _nameCtrl.text.trim(),
          category: _category,
          unit: _unitCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        );
      } else {
        await notifier.createBlank(
          name: _nameCtrl.text.trim(),
          category: _category,
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
        setState(() => _saving = false);
        showTopSnackBar(context, e.toString());
      }
    }
  }

  String _categoryLabel(String slug) =>
      '${categoryEmojiMap[slug] ?? ''} ${categoryMap[slug] ?? slug}'.trim();

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
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
                  final selected = validSlugs.contains(_category)
                      ? _category
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
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _category = v);
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
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text(BlanksLabels.actionCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
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
    final selected =
        categoryMap.containsKey(_category) ? _category : null;
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
      onChanged: (v) {
        if (v != null) {
          setState(() => _category = v);
        }
      },
    );
  }
}