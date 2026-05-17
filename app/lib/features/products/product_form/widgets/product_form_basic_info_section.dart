import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/models/category.dart';
import '../../../../shared/labels/products.dart';

class ProductFormBasicInfoSection extends StatelessWidget {
  const ProductFormBasicInfoSection({
    super.key,
    required this.productId,
    required this.pickedPhoto,
    required this.baseUrl,
    required this.onPickPhoto,
    required this.cacheBuster,
    required this.nameController,
    required this.codeController,
    required this.currentPrefix,
    required this.categoriesAsync,
    required this.category,
    required this.onCategoryChanged,
    required this.photoSection,
  });

  final int? productId;
  final XFile? pickedPhoto;
  final String baseUrl;
  final VoidCallback onPickPhoto;
  final String? cacheBuster;
  final TextEditingController nameController;
  final TextEditingController codeController;
  final String currentPrefix;
  final AsyncValue<List<Category>> categoriesAsync;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final Widget photoSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        photoSection,
        const SizedBox(height: 24),
        TextFormField(
          controller: nameController,
          decoration: const InputDecoration(labelText: VN.productName),
          validator: (v) => (v == null || v.trim().isEmpty) ? VN.fieldRequired : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: codeController,
          decoration: InputDecoration(
            labelText: VN.productCode,
            prefixText: currentPrefix.isNotEmpty ? '$currentPrefix-' : null,
            hintText: currentPrefix.isEmpty ? 'VD: BKS-16' : '16',
            helperText: 'Tự động tạo nếu để trống',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 16),
        categoriesAsync.when(
          loading: () => _fallbackCategoryDropdown(
            category,
            labelResolver: (slug) => '${categoryEmojiMap[slug] ?? ''} ${categoryMap[slug] ?? slug}',
          ),
          error: (_, _) => _fallbackCategoryDropdown(
            categoryMap.containsKey(category) ? category : categoryMap.keys.first,
            labelResolver: (slug) => '${categoryEmojiMap[slug] ?? ''} ${categoryMap[slug] ?? slug}',
          ),
          data: (categories) {
            final active = categories.where((c) => c.active == 1).toList();
            final validSlugs = active.map((c) => c.slug).toList();
            final selected = validSlugs.contains(category) && validSlugs.isNotEmpty
                ? category
                : (validSlugs.isNotEmpty ? validSlugs.first : category);
            return DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: VN.productCategory),
              items: active
                  .map(
                    (cat) => DropdownMenuItem(
                      value: cat.slug,
                      child: Text('${categoryEmojiMap[cat.slug] ?? ''} ${cat.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onCategoryChanged(v);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _fallbackCategoryDropdown(String initialValue, {required String Function(String slug) labelResolver}) {
    return DropdownButtonFormField<String>(
      initialValue: initialValue,
      decoration: const InputDecoration(labelText: VN.productCategory),
      items: categoryMap.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(labelResolver(e.key))))
          .toList(),
      onChanged: (v) {
        if (v != null) onCategoryChanged(v);
      },
    );
  }
}
