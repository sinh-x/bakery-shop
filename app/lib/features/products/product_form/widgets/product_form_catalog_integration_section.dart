import 'package:flutter/material.dart';

class ProductFormCatalogIntegrationSection extends StatelessWidget {
  const ProductFormCatalogIntegrationSection({
    super.key,
    required this.isEditing,
    required this.catalogGallery,
  });

  final bool isEditing;
  final Widget catalogGallery;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        const SizedBox(height: 32),
        catalogGallery,
      ],
    );
  }
}
