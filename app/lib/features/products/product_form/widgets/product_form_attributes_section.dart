import 'package:flutter/material.dart';

import '../../../../shared/labels/products.dart';

class ProductFormAttributesSection extends StatelessWidget {
  const ProductFormAttributesSection({
    super.key,
    required this.enumOptionsSection,
    required this.notesController,
    required this.rutTien,
    required this.trungBay,
    required this.tangKem,
    required this.isEditing,
    required this.onRutTienChanged,
    required this.onTrungBayChanged,
    required this.onTangKemChanged,
  });

  final Widget enumOptionsSection;
  final TextEditingController notesController;
  final bool rutTien;
  final bool trungBay;
  final bool tangKem;
  final bool isEditing;
  final ValueChanged<bool> onRutTienChanged;
  final ValueChanged<bool> onTrungBayChanged;
  final ValueChanged<bool> onTangKemChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        enumOptionsSection,
        TextFormField(
          controller: notesController,
          decoration: const InputDecoration(labelText: VN.productNotes),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          value: rutTien,
          onChanged: onRutTienChanged,
          title: const Text(VN.rutTienToggle),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: trungBay,
          onChanged: isEditing ? onTrungBayChanged : null,
          title: const Text(VN.trungBay),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: tangKem,
          onChanged: isEditing ? onTangKemChanged : null,
          title: const Text(VN.tangKem),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }
}
