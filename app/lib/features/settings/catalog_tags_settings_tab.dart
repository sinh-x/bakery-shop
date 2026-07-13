import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/catalog_tag.dart';
import '../../data/api/config_service.dart';
import '../../providers/catalog_provider.dart';
import '../../shared/labels/shared.dart';

class CatalogTagsSettingsTab extends ConsumerWidget {
  const CatalogTagsSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(catalogTagDefsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: tagsAsync.when(
        data: (tags) => _TagList(tags: tags, ref: ref),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error: $err'),
        ),
      ),
    );
  }
}

class _TagList extends StatelessWidget {
  const _TagList({required this.tags, required this.ref});

  final List<CatalogTagDef> tags;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    // Group tags by category in fixed order: Đối tượng → Dịp → Phong cách
    final objectTags = <CatalogTagDef>[];
    final occasionTags = <CatalogTagDef>[];
    final styleTags = <CatalogTagDef>[];

    for (final tag in tags) {
      switch (tag.category) {
        case 'doi_tuong':
          objectTags.add(tag);
        case 'dip':
          occasionTags.add(tag);
        case 'phong_cach':
          styleTags.add(tag);
      }
    }

    // Sort each group alphabetically by label
    objectTags.sort((a, b) => a.label.compareTo(b.label));
    occasionTags.sort((a, b) => a.label.compareTo(b.label));
    styleTags.sort((a, b) => a.label.compareTo(b.label));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Group: Đối tượng
        _TagGroup(
          category: 'doi_tuong',
          tags: objectTags,
        ),
        const SizedBox(height: 24),

        // Group: Dịp
        _TagGroup(
          category: 'dip',
          tags: occasionTags,
        ),
        const SizedBox(height: 24),

        // Group: Phong cách
        _TagGroup(
          category: 'phong_cach',
          tags: styleTags,
        ),
      ],
    );
  }
}

class _TagGroup extends StatelessWidget {
  const _TagGroup({required this.category, required this.tags});

  final String category;
  final List<CatalogTagDef> tags;

  String _getCategoryLabel() {
    switch (category) {
      case 'doi_tuong':
        return VN.doiTuong;
      case 'dip':
        return VN.dip;
      case 'phong_cach':
        return VN.phongCach;
      default:
        return category;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header with category label and count
        Row(
          children: [
            Text(
              _getCategoryLabel(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${tags.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Tag list or placeholder
        if (tags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              VN.noTagsInCategory,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          )
        else
          ...[
            for (final tag in tags)
              Consumer(
                builder: (context, ref, child) {
                  return _TagRow(tag: tag);
                },
              ),
          ],
      ],
    );
  }
}

class _TagRow extends ConsumerWidget {
  const _TagRow({required this.tag});

  final CatalogTagDef tag;
  


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Coloured chip preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getColor(tag.category),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              tag.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Key text in monospace
          Expanded(
            child: Text(
              tag.key,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Edit button
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () {
              _showEditDialog(context, ref, tag);
            },
          ),

          // Delete button
          IconButton(
            icon: const Icon(Icons.delete, size: 20),
            onPressed: () {
              _showDeleteDialog(context, ref, tag);
            },
          ),
        ],
      ),
    );
  }

  Color _getColor(String category) {
    switch (category) {
      case 'doi_tuong': // audience
        return const Color(0xFF2196F3);
      case 'dip': // occasion
        return const Color(0xFFFF9800);
      case 'phong_cach': // style
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey.shade300;
    }
  }
}

Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
  final formKey = GlobalKey<FormState>();
  final keyCtrl = TextEditingController();
  final labelCtrl = TextEditingController();
  
  String? selectedCategory;
  final categories = ['doi_tuong', 'dip', 'phong_cach'];
  
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
                      child: Text(_getCategoryLabel(category)),
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
                    final regex = RegExp(r'^[a-z0-9][a-z0-9-]*$');
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
                      return 'Nhãn không được vượt quá 40 ký tự';
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
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
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

Future<void> _showEditDialog(BuildContext context, WidgetRef ref, CatalogTagDef tag) async {
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
              child: Text(_getCategoryLabel(tag.category)),
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
                final regex = RegExp(r'^[a-z0-9][a-z0-9-]*$');
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
                  return 'Nhãn không được vượt quá 40 ký tự';
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
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(ctx, true);
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

Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref, CatalogTagDef tag) async {
  try {
    // Check tag usage
    final usage = await ref.read(configServiceProvider).getTagUsage('${tag.category}:${tag.key}');
    
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
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(VN.tagDeleted)),
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
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi kiểm tra sử dụng thẻ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

String _getCategoryLabel(String category) {
  switch (category) {
    case 'doi_tuong':
      return VN.doiTuong;
    case 'dip':
      return VN.dip;
    case 'phong_cach':
      return VN.phongCach;
    default:
      return category;
  }
}