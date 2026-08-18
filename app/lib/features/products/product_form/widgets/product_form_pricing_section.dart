import 'package:flutter/material.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
class ProductFormPricingSection extends StatelessWidget {
  const ProductFormPricingSection({
    super.key,
    required this.priceController,
    required this.costController,
    required this.priceChipSection,
  });

  final TextEditingController priceController;
  final TextEditingController costController;
  final Widget priceChipSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: priceController,
          decoration: const InputDecoration(
            labelText: ProductsLabels.productPrice,
            suffixText: SharedLabels.currency,
          ),
          keyboardType: TextInputType.number,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return SharedLabels.fieldRequired;
            if (double.tryParse(v) == null) return SharedLabels.invalidPrice;
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: costController,
          decoration: const InputDecoration(
            labelText: ProductsLabels.productCost,
            suffixText: SharedLabels.currency,
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        priceChipSection,
      ],
    );
  }
}
