import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../data/providers/categories_provider.dart';
import '../../providers/form_draft_session_notifier.dart';
import '../../shared/models/form_draft_context.dart';
import '../../shared/widgets/discard_form_draft_action.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'providers/category_form_notifier.dart';
import 'widgets/icon_cell.dart';
import 'widgets/upper_case_formatter.dart';

/// Curated emoji options for category icons.
const categoryEmojiOptions = [
  '🎂',
  '🧁',
  '🍰',
  '🍩',
  '🍪',
  '🍫',
  '🍬',
  '🥐',
  '🍞',
  '🥖',
  '🧇',
  '🍮',
  '🥧',
  '🍡',
  '🧃',
  '☕',
  '🍵',
  '🥤',
  '🍽️',
  '🛒',
];

/// Show the add/edit category bottom sheet.
///
/// Pass [category] for edit mode; omit for add mode.
Future<void> showCategoryForm(BuildContext context, {Category? category}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _CategoryForm(category: category),
  );
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.category});

  final Category? category;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codePrefixCtrl;
  late final TextEditingController _slugCtrl;

  bool get _isEditing => widget.category != null;
  late final FormDraftContext _draftContext;

  NotifierProvider<CategoryFormNotifier, CategoryFormState> get _provider =>
      contextualCategoryFormProvider(_draftContext);

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _draftContext = FormDraftContext(
      formType: 'category',
      mode: _isEditing ? FormDraftMode.edit : FormDraftMode.create,
      entityId: c?.id.toString(),
    );
    final formNotifier = ref.read(_provider.notifier);
    final draft = formNotifier.newDraft;
    final restore = formNotifier.hasRetainedDraft;
    _nameCtrl = TextEditingController(
      text: restore ? draft.name : c?.name ?? '',
    );
    _codePrefixCtrl = TextEditingController(
      text: restore ? draft.codePrefix : c?.codePrefix ?? '',
    );
    _slugCtrl = TextEditingController(
      text: restore ? draft.slug : c?.slug ?? '',
    );
    final seedId = c?.id;
    final seedIcon = c?.icon;
    final seedActive = (c?.active ?? 1) == 1;
    // Deferred to a microtask so we don't mutate providers during the
    // widget-tree build phase (DG-404 Phase 4.7).
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(_provider.notifier)
          .seed(
            editingId: seedId,
            name: c?.name,
            codePrefix: c?.codePrefix,
            slug: c?.slug,
            icon: seedIcon,
            active: seedActive,
          );
    });
    if (!_isEditing) {
      _nameCtrl.addListener(_onNameChanged);
    }
    _nameCtrl.addListener(_retainNewDraft);
    _codePrefixCtrl.addListener(_retainNewDraft);
    _slugCtrl.addListener(_retainNewDraft);
  }

  void _onNameChanged() {
    _slugCtrl.text = _slugify(_nameCtrl.text);
  }

  void _retainNewDraft() {
    ref
        .read(_provider.notifier)
        .updateNewDraft(
          name: _nameCtrl.text,
          codePrefix: _codePrefixCtrl.text,
          slug: _slugCtrl.text,
        );
  }

  String _slugify(String text) {
    const viMap = {
      'á': 'a',
      'à': 'a',
      'ả': 'a',
      'ã': 'a',
      'ạ': 'a',
      'ă': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ẵ': 'a',
      'ằ': 'a',
      'ẳ': 'a',
      'â': 'a',
      'ấ': 'a',
      'ầ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ậ': 'a',
      'đ': 'd',
      'é': 'e',
      'è': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ẹ': 'e',
      'ê': 'e',
      'ế': 'e',
      'ề': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ệ': 'e',
      'í': 'i',
      'ì': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ị': 'i',
      'ó': 'o',
      'ò': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ọ': 'o',
      'ô': 'o',
      'ố': 'o',
      'ồ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ộ': 'o',
      'ơ': 'o',
      'ớ': 'o',
      'ờ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ợ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ụ': 'u',
      'ư': 'u',
      'ứ': 'u',
      'ừ': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ự': 'u',
      'ý': 'y',
      'ỳ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'ỵ': 'y',
    };

    var result = text.toLowerCase();
    for (final entry in viMap.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
  }

  @override
  void dispose() {
    if (!_isEditing) {
      _nameCtrl.removeListener(_onNameChanged);
    }
    _nameCtrl.dispose();
    _codePrefixCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final formNotifier = ref.read(_provider.notifier);
    final formState = ref.read(_provider);
    final submittedDraft = formNotifier.draftSnapshot;
    formNotifier.setSaving(true);
    try {
      final notifier = ref.read(categoriesProvider.notifier);
      if (_isEditing) {
        await notifier.updateCategory(
          widget.category!.id,
          name: _nameCtrl.text.trim(),
          codePrefix: _codePrefixCtrl.text.trim().toUpperCase(),
          active: formState.isActive ? 1 : 0,
          icon: formState.selectedIcon,
        );
      } else {
        await notifier.createCategory(
          name: _nameCtrl.text.trim(),
          slug: _slugCtrl.text.trim(),
          codePrefix: _codePrefixCtrl.text.trim().toUpperCase(),
          icon: formState.selectedIcon,
        );
      }
      formNotifier.clearAfterSuccess(submittedDraft);
      formNotifier.setSaving(false);
      if (mounted) {
        Navigator.of(context).pop();
        showTopSnackBar(
          context,
          _isEditing
              ? ProductsLabels.categoryUpdated
              : ProductsLabels.categoryCreated,
        );
      }
    } catch (e) {
      formNotifier.setSaving(false);
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    }
  }

  Widget _buildIconPicker(ColorScheme colorScheme) {
    final selectedIcon = ref.watch(_provider).selectedIcon;
    final formNotifier = ref.read(_provider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          ProductsLabels.categoryIcon,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: categoryEmojiOptions.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final selected = selectedIcon.isEmpty;
                return IconCell(
                  selected: selected,
                  colorScheme: colorScheme,
                  onTap: () => formNotifier.setSelectedIcon(''),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : Colors.grey,
                  ),
                );
              }
              final emoji = categoryEmojiOptions[index - 1];
              final selected = selectedIcon == emoji;
              return IconCell(
                selected: selected,
                colorScheme: colorScheme,
                onTap: () => formNotifier.setSelectedIcon(emoji),
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final formState = ref.watch(_provider);
    final isActive = formState.isActive;
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
                    ? ProductsLabels.editCategory
                    : ProductsLabels.addCategory,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: ProductsLabels.categoryName,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? SharedLabels.fieldRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codePrefixCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  UpperCaseFormatter(),
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: ProductsLabels.codePrefix,
                  hintText: ProductsLabels.codePrefixHint,
                  helperText: ProductsLabels.codePrefixHelp,
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return ProductsLabels.noPrefixError;
                  }
                  if (!RegExp(r'^[A-Z]{2,4}$').hasMatch(v.trim())) {
                    return ProductsLabels.prefixFormatError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _slugCtrl,
                readOnly: _isEditing,
                decoration: InputDecoration(
                  labelText: ProductsLabels.categorySlug,
                  border: const OutlineInputBorder(),
                  filled: _isEditing,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? SharedLabels.fieldRequired
                    : null,
              ),
              const SizedBox(height: 16),
              if (_isEditing) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: const Text(ProductsLabels.categoryVisibility),
                    subtitle: Text(
                      isActive
                          ? ProductsLabels.categoryVisible
                          : ProductsLabels.categoryHiddenState,
                    ),
                    value: isActive,
                    onChanged: saving
                        ? null
                        : (value) {
                            ref.read(_provider.notifier).setIsActive(value);
                          },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _buildIconPicker(colorScheme),
              DiscardFormDraftAction(
                isDirty: ref
                    .watch(formDraftSessionProvider)
                    .containsKey(_draftContext),
                onDiscard: () {
                  ref.read(_provider.notifier).clearNewDraft();
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text(SharedLabels.cancel),
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
                        : const Text(SharedLabels.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
