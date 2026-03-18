import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../providers/categories_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

/// Show the add/edit category bottom sheet.
///
/// Pass [category] for edit mode; omit for add mode.
Future<void> showCategoryForm(
  BuildContext context, {
  Category? category,
}) {
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
  bool _saving = false;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _codePrefixCtrl = TextEditingController(text: c?.codePrefix ?? '');
    _slugCtrl = TextEditingController(text: c?.slug ?? '');
    if (!_isEditing) {
      _nameCtrl.addListener(_onNameChanged);
    }
  }

  void _onNameChanged() {
    _slugCtrl.text = _slugify(_nameCtrl.text);
  }

  String _slugify(String text) {
    const viMap = {
      'á': 'a', 'à': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ắ': 'a', 'ặ': 'a', 'ẵ': 'a', 'ằ': 'a', 'ẳ': 'a',
      'â': 'a', 'ấ': 'a', 'ầ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'đ': 'd',
      'é': 'e', 'è': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ế': 'e', 'ề': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'í': 'i', 'ì': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ó': 'o', 'ò': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ố': 'o', 'ồ': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ớ': 'o', 'ờ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ú': 'u', 'ù': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ứ': 'u', 'ừ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ý': 'y', 'ỳ': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
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
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final notifier = ref.read(categoriesProvider.notifier);
      if (_isEditing) {
        await notifier.updateCategory(
          widget.category!.id,
          name: _nameCtrl.text.trim(),
          codePrefix: _codePrefixCtrl.text.trim().toUpperCase(),
        );
      } else {
        await notifier.createCategory(
          name: _nameCtrl.text.trim(),
          slug: _slugCtrl.text.trim(),
          codePrefix: _codePrefixCtrl.text.trim().toUpperCase(),
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(_isEditing ? VN.categoryUpdated : VN.categoryCreated),
          ),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? VN.editCategory : VN.addCategory,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: VN.categoryName,
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? VN.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codePrefixCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                _UpperCaseFormatter(),
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(
                labelText: VN.codePrefix,
                hintText: VN.codePrefixHint,
                helperText: VN.codePrefixHelp,
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return VN.noPrefixError;
                if (!RegExp(r'^[A-Z]{2,4}$').hasMatch(v.trim())) {
                  return VN.prefixFormatError;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _slugCtrl,
              readOnly: _isEditing,
              decoration: InputDecoration(
                labelText: VN.categorySlug,
                border: const OutlineInputBorder(),
                filled: _isEditing,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? VN.fieldRequired : null,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text(VN.cancel),
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
                      : const Text(VN.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
