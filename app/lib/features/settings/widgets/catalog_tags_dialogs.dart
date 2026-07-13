import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/labels/shared.dart';
import '../../../shared/helpers/catalog_tag_helpers.dart';
import '../../../data/models/catalog_tag.dart';
import '../../../data/api/config_service.dart';
import '../../../providers/catalog_provider.dart';

Future<void> showAddDialog(BuildContext context, WidgetRef ref) async {
  final formKey = GlobalKey<FormState>();
  final keyCtrl = TextEditingController();
  final labelCtrl = TextEditingController();
  
  String? selectedCategory;
  final categories = [VN.tagCategoriesDoiTuong, VN.tagCategoriesDip, VN.tagCategoriesPhongCach];
  
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text(VN.addCatalogTag),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: VN.tagCategory,
                    border: OutlineInputBorder(),
                  ),
                  items: categories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(getCategoryLabel(category)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCategory = value;
                    });
                  },
                  validator: (value) => value == null ? VN.fieldRequired : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                    labelText: VN.tagKey,
                    hintText: VN.tagKeyHint,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return VN.fieldRequired;
                    }
                    // Regex validation: ^[a-z0-9][a-z0-9-]*
                    final regex = RegExp(VN.tagKeyRegexPattern);
                    if (!regex.hasMatch(value)) {
                      return VN.tagKeyInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: VN.tagLabel,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return VN.tagLabelEmpty;
                    }
                    if (value.length > 40) {
                  return VN.tagLabelTooLong;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(VN.cancel),
            ),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  // Don't pop immediately, run the mutation first
                  try {
                    final value = '${selectedCategory!}:${keyCtrl.text.trim()}:${labelCtrl.text.trim()}';
                    await ref.read(configServiceProvider).createConfigValue('catalog_tag', value);
                    ref.invalidate(catalogTagDefsProvider);
                    ref.invalidate(catalogBrowseProvider);
                    if (ctx.mounted) {
                      Navigator.pop(ctx, true);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text(VN.tagAdded)),
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text('${VN.tagGenericError}$e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text(VN.save),
            ),
          ],
        );
      },
    ),
  );

  if (confirmed == true) {
    try {
      final value = '${selectedCategory!}:${keyCtrl.text.trim()}:${labelCtrl.text.trim()}';
      await ref.read(configServiceProvider).createConfigValue('catalog_tag', value);
      ref.invalidate(catalogTagDefsProvider);
      ref.invalidate(catalogBrowseProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VN.tagAdded)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  keyCtrl.dispose();
  labelCtrl.dispose();
}

Future<void> showEditDialog(BuildContext context, WidgetRef ref, CatalogTagDef tag) async {
  final formKey = GlobalKey<FormState>();
  final keyCtrl = TextEditingController(text: tag.key);
  final labelCtrl = TextEditingController(text: tag.label);
  
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(VN.editCatalogTag),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Category dropdown (disabled in v1)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: VN.tagCategory,
                border: OutlineInputBorder(),
              ),
              child: Text(getCategoryLabel(tag.category)),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: keyCtrl,
              decoration: const InputDecoration(
                labelText: VN.tagKey,
                hintText: VN.tagKeyHint,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return VN.fieldRequired;
                }
                // Regex validation: ^[a-z0-9][a-z0-9-]*
                final regex = RegExp(VN.tagKeyRegexPattern);
                if (!regex.hasMatch(value)) {
                  return VN.tagKeyInvalid;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: VN.tagLabel,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return VN.tagLabelEmpty;
                }
                if (value.length > 40) {
                  return VN.tagLabelTooLong;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(VN.cancel),
        ),
        FilledButton(
          onPressed: () async {
            if (formKey.currentState!.validate()) {
              // Don't pop immediately, run the mutation first
              try {
                final oldValue = '${tag.category}:${tag.key}:${tag.label}';
                final newValue = '${tag.category}:${keyCtrl.text.trim()}:${labelCtrl.text.trim()}';
                await ref.read(configServiceProvider).updateConfigValue('catalog_tag', oldValue, newValue);
                ref.invalidate(catalogTagDefsProvider);
                ref.invalidate(catalogBrowseProvider);
                if (ctx.mounted) {
                  Navigator.pop(ctx, true);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text(VN.tagUpdated)),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('${VN.tagGenericError}$e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          },
          child: const Text(VN.save),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    try {
      final oldValue = '${tag.category}:${tag.key}:${tag.label}';
      final newValue = '${tag.category}:${keyCtrl.text.trim()}:${labelCtrl.text.trim()}';
      await ref.read(configServiceProvider).updateConfigValue('catalog_tag', oldValue, newValue);
      ref.invalidate(catalogTagDefsProvider);
      ref.invalidate(catalogBrowseProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VN.tagUpdated)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  keyCtrl.dispose();
  labelCtrl.dispose();
}

Future<void> showDeleteDialog(BuildContext context, WidgetRef ref, CatalogTagDef tag) async {
  try {
    // Check tag usage
    final usage = await ref.read(configServiceProvider).getTagUsage(tag.key);
    
    if (usage.count > 0) {
      // Show blocking dialog
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(VN.tagCannotDelete),
            content: Text(VN.tagInUse(usage.count)),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(VN.save),
              ),
            ],
          ),
        );
      }
    } else {
      // Show confirmation dialog
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(VN.tagDeleteConfirm(tag.label)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(VN.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(VN.remove),
            ),
          ],
        ),
      );
      
      if (confirmed == true) {
        try {
          final value = '${tag.category}:${tag.key}:${tag.label}';
          await ref.read(configServiceProvider).deleteConfigValue('catalog_tag', value);
          ref.invalidate(catalogTagDefsProvider);
          ref.invalidate(catalogBrowseProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(VN.tagDeleted)),
            );
          }
        } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${VN.tagGenericError}$e'),
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
          content: Text('${VN.tagUsageCheckError}$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
