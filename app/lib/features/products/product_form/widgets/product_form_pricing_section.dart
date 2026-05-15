import 'package:flutter/material.dart';

import '../../../../shared/labels/products.dart';

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
            labelText: VN.productPrice,
            suffixText: VN.currency,
          ),
          keyboardType: TextInputType.number,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return VN.fieldRequired;
            if (double.tryParse(v) == null) return VN.invalidPrice;
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: costController,
          decoration: const InputDecoration(
            labelText: VN.productCost,
            suffixText: VN.currency,
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        priceChipSection,
      ],
    );
  }
}
