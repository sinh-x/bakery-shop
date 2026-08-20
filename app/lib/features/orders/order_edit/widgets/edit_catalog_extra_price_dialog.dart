import 'package:bakery_app/shared/utils.dart' show formatVND, showTopSnackBar;
import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import '../../../../data/models/product.dart';
import 'edit_catalog_extra_selection.dart';

class EditCatalogExtraPriceDialog extends StatefulWidget {
  const EditCatalogExtraPriceDialog({super.key, required this.product});

  final Product product;

  @override
  State<EditCatalogExtraPriceDialog> createState() =>
      _EditCatalogExtraPriceDialogState();
}

class _EditCatalogExtraPriceDialogState
    extends State<EditCatalogExtraPriceDialog> {
  static const int _manualOptionId = -999;
  final TextEditingController _manualCtrl = TextEditingController();
  late int _selectedOptionId;

  @override
  void initState() {
    super.initState();
    _selectedOptionId = 0;
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = <(int id, String label, double price, int? chipId)>[
      (0, StockLabels.giaCoSo, widget.product.basePrice, null),
      ...widget.product.priceChips.map(
        (chip) => (chip.id, chip.label, chip.price, chip.id),
      ),
      (_manualOptionId, StockLabels.donGiaNhapTay, widget.product.basePrice, null),
    ];

    return AlertDialog(
      title: Text(widget.product.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) {
              final selected = _selectedOptionId == option.$1;
              return ChoiceChip(
                label: Text('${option.$2} (${formatVND(option.$3)})'),
                selected: selected,
                onSelected: (_) => setState(() => _selectedOptionId = option.$1),
              );
            }).toList(),
          ),
          if (_selectedOptionId == _manualOptionId) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _manualCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: OrdersLabels.itemPrice,
                suffixText: 'đ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_selectedOptionId == _manualOptionId) {
              final manualPrice = double.tryParse(_manualCtrl.text.trim());
              if (manualPrice == null || manualPrice < 0) {
                showTopSnackBar(context, SharedLabels.invalidPrice);
                return;
              }
              Navigator.pop(
                context,
                EditCatalogExtraSelection(customUnitPrice: manualPrice),
              );
              return;
            }

            final selected = options.firstWhere((o) => o.$1 == _selectedOptionId);
            if (selected.$4 == null) {
              Navigator.pop(
                context,
                const EditCatalogExtraSelection(customUnitPrice: null),
              );
            } else {
              Navigator.pop(
                context,
                EditCatalogExtraSelection(priceChipId: selected.$4),
              );
            }
          },
          child: const Text(OrdersLabels.xacNhan),
        ),
      ],
    );
  }
}