import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/helpers/catalog_tag_helpers.dart';
import '../../../data/models/catalog_tag.dart';
import '../../../data/api/config_service.dart';
import '../../../data/providers/catalog_provider.dart';
import '../../../providers/form_draft_session_notifier.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import '../providers/catalog_tag_form_notifier.dart';

Future<void> showAddDialog(BuildContext context, WidgetRef ref) async {
  if (!context.mounted) return;
  ref.read(catalogTagFormOperationProvider.notifier).setSaving(false);
  await showDialog<bool>(
    context: context,
    builder: (ctx) => const _AddTagDialog(),
  );
}

Future<void> showEditDialog(
  BuildContext context,
  WidgetRef ref,
  CatalogTagDef tag,
) async {
  if (!context.mounted) return;
  await showDialog<bool>(
    context: context,
    builder: (ctx) => _EditTagDialog(tag: tag),
  );
}

Future<void> showDeleteDialog(
  BuildContext context,
  WidgetRef ref,
  CatalogTagDef tag,
) async {
  try {
    final usage = await ref.read(configServiceProvider).getTagUsage(tag.key);

    if (usage.count > 0) {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(ProductsLabels.tagCannotDelete),
            content: Text(ProductsLabels.tagInUse(usage.count)),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(SharedLabels.save),
              ),
            ],
          ),
        );
      }
    } else {
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ProductsLabels.tagDeleteConfirm(tag.label)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(SharedLabels.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(SharedLabels.remove),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          final value = '${tag.category}:${tag.key}:${tag.label}';
          await ref
              .read(configServiceProvider)
              .deleteConfigValue('catalog_tag', value);
          ref.invalidate(catalogTagDefsProvider);
          ref.invalidate(catalogBrowseProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(ProductsLabels.tagDeleted)),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${ProductsLabels.tagGenericError}$e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ProductsLabels.tagUsageCheckError}$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _AddTagDialog extends ConsumerStatefulWidget {
  const _AddTagDialog();

  @override
  ConsumerState<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends ConsumerState<_AddTagDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _keyCtrl;
  late final TextEditingController _labelCtrl;
  static final _categories = [
    ProductsLabels.tagCategoriesDoiTuong,
    ProductsLabels.tagCategoriesDip,
    ProductsLabels.tagCategoriesPhongCach,
  ];

  @override
  void initState() {
    super.initState();
    final draft = ref.read(catalogTagFormProvider);
    _keyCtrl = TextEditingController(text: draft.key)..addListener(_persistKey);
    _labelCtrl = TextEditingController(text: draft.label)
      ..addListener(_persistLabel);
  }

  void _persistKey() =>
      ref.read(catalogTagFormProvider.notifier).setKey(_keyCtrl.text);

  void _persistLabel() =>
      ref.read(catalogTagFormProvider.notifier).setLabel(_labelCtrl.text);

  @override
  void dispose() {
    _keyCtrl.removeListener(_persistKey);
    _labelCtrl.removeListener(_persistLabel);
    _keyCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final operation = ref.read(catalogTagFormOperationProvider.notifier);
    final registry = ref.read(formDraftSessionProvider.notifier);
    final submittedDraft =
        ref.read(formDraftSessionProvider)[catalogTagCreateContext]
            as CatalogTagFormState?;
    final configService = ref.read(configServiceProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    operation.setSaving(true);
    final selectedCategory = ref.read(catalogTagFormProvider).selectedCategory;
    try {
      final value =
          '$selectedCategory:${_keyCtrl.text.trim()}:${_labelCtrl.text.trim()}';
      await configService.createConfigValue('catalog_tag', value);
      container.invalidate(catalogTagDefsProvider);
      container.invalidate(catalogBrowseProvider);
      if (submittedDraft != null) {
        registry.clearDraftIfUnchanged(catalogTagCreateContext, submittedDraft);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(ProductsLabels.tagAdded)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ProductsLabels.tagGenericError}$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      operation.setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCategory = ref.watch(catalogTagFormProvider).selectedCategory;
    final draft = ref.watch(catalogTagFormProvider);
    final saving = ref.watch(catalogTagFormOperationProvider);
    return AlertDialog(
      title: const Text(ProductsLabels.addCatalogTag),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              decoration: const InputDecoration(
                labelText: ProductsLabels.tagCategory,
                border: OutlineInputBorder(),
              ),
              items: _categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(getCategoryLabel(category)),
                );
              }).toList(),
              onChanged: (value) {
                ref
                    .read(catalogTagFormProvider.notifier)
                    .setSelectedCategory(value);
              },
              validator: (value) =>
                  value == null ? SharedLabels.fieldRequired : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _keyCtrl,
              decoration: const InputDecoration(
                labelText: ProductsLabels.tagKey,
                hintText: ProductsLabels.tagKeyHint,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return SharedLabels.fieldRequired;
                }
                final regex = RegExp(ProductsLabels.tagKeyRegexPattern);
                if (!regex.hasMatch(value)) {
                  return ProductsLabels.tagKeyInvalid;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: ProductsLabels.tagLabel,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return ProductsLabels.tagLabelEmpty;
                }
                if (value.length > 40) {
                  return ProductsLabels.tagLabelTooLong;
                }
                if (value.contains(':')) {
                  return ProductsLabels.tagLabelNoColon;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        DiscardFormDraftAction(
          isDirty: draft.isDirty,
          onDiscard: () {
            ref.read(catalogTagFormProvider.notifier).clear();
            _keyCtrl.clear();
            _labelCtrl.clear();
          },
        ),
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(SharedLabels.save),
        ),
      ],
    );
  }
}

class _EditTagDialog extends ConsumerStatefulWidget {
  const _EditTagDialog({required this.tag});

  final CatalogTagDef tag;

  @override
  ConsumerState<_EditTagDialog> createState() => _EditTagDialogState();
}

class _EditTagDialogState extends ConsumerState<_EditTagDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _keyCtrl = TextEditingController(text: widget.tag.key);
  late final _labelCtrl = TextEditingController(text: widget.tag.label);

  @override
  void dispose() {
    _keyCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final configService = ref.read(configServiceProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final oldValue =
          '${widget.tag.category}:${widget.tag.key}:${widget.tag.label}';
      final newValue =
          '${widget.tag.category}:${_keyCtrl.text.trim()}:${_labelCtrl.text.trim()}';
      await configService.updateConfigValue('catalog_tag', oldValue, newValue);
      container.invalidate(catalogTagDefsProvider);
      container.invalidate(catalogBrowseProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ProductsLabels.tagUpdated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ProductsLabels.tagGenericError}$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(ProductsLabels.editCatalogTag),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InputDecorator(
              decoration: const InputDecoration(
                labelText: ProductsLabels.tagCategory,
                border: OutlineInputBorder(),
              ),
              child: Text(getCategoryLabel(widget.tag.category)),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _keyCtrl,
              decoration: const InputDecoration(
                labelText: ProductsLabels.tagKey,
                hintText: ProductsLabels.tagKeyHint,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return SharedLabels.fieldRequired;
                }
                final regex = RegExp(ProductsLabels.tagKeyRegexPattern);
                if (!regex.hasMatch(value)) {
                  return ProductsLabels.tagKeyInvalid;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: ProductsLabels.tagLabel,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return ProductsLabels.tagLabelEmpty;
                }
                if (value.length > 40) {
                  return ProductsLabels.tagLabelTooLong;
                }
                if (value.contains(':')) {
                  return ProductsLabels.tagLabelNoColon;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton(onPressed: _save, child: const Text(SharedLabels.save)),
      ],
    );
  }
}
