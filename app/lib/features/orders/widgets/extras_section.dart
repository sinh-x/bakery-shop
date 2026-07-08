import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order_draft.dart';
import '../../../data/models/product.dart';
import '../../../providers/products_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'stage1_extras_states.dart';

/// Result of the catalog-extra price selection dialog.
class CatalogExtraSelection {
  const CatalogExtraSelection({this.priceChipId, this.customUnitPrice});

  final int? priceChipId;
  final double? customUnitPrice;
}

/// Dialog for choosing a price (base / chip / manual) when adding a catalog
/// extra (phu_kien) product as a paid extra or gift.
///
/// Ported from the legacy `order_edit_screen.dart` `_CatalogExtraPriceDialog`
/// (commit bd17e17) so the Stage 1 create flow can reuse the same pattern.
class CatalogExtraPriceDialog extends StatefulWidget {
  const CatalogExtraPriceDialog({super.key, required this.product});

  final Product product;

  @override
  State<CatalogExtraPriceDialog> createState() =>
      _CatalogExtraPriceDialogState();
}

class _CatalogExtraPriceDialogState extends State<CatalogExtraPriceDialog> {
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
      (0, VN.giaCoSo, widget.product.basePrice, null),
      ...widget.product.priceChips.map(
        (chip) => (chip.id, chip.label, chip.price, chip.id),
      ),
      (_manualOptionId, VN.donGiaNhapTay, widget.product.basePrice, null),
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
                labelText: VN.itemPrice,
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
          child: const Text(VN.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_selectedOptionId == _manualOptionId) {
              final manualPrice = double.tryParse(_manualCtrl.text.trim());
              if (manualPrice == null || manualPrice < 0) {
                showTopSnackBar(context, VN.invalidPrice);
                return;
              }
              Navigator.pop(
                context,
                CatalogExtraSelection(customUnitPrice: manualPrice),
              );
              return;
            }

            final selected = options.firstWhere((o) => o.$1 == _selectedOptionId);
            if (selected.$4 == null) {
              Navigator.pop(
                context,
                const CatalogExtraSelection(customUnitPrice: null),
              );
            } else {
              Navigator.pop(
                context,
                CatalogExtraSelection(priceChipId: selected.$4),
              );
            }
          },
          child: const Text(VN.xacNhan),
        ),
      ],
    );
  }
}

/// Section that renders ActionChips for each active `phu_kien` catalog product,
/// allowing staff to add them as paid extras or gifts.
///
/// On tap, a [CatalogExtraPriceDialog] opens to choose base/chip/manual price.
/// The selected product is then added via [onAddCatalogExtra] using
/// [createCatalogExtraItem].
class ExtrasSection extends ConsumerWidget {
  const ExtrasSection({
    super.key,
    required this.onAddCatalogExtra,
  });

  /// Called with the chosen product, price-chip/manual price, and gift flag.
  final void Function(
    Product product,
    int? priceChipId,
    double? customUnitPrice,
  ) onAddCatalogExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extrasAsync = ref.watch(phuKienProductsProvider);
    final theme = Theme.of(context);

    return extrasAsync.when(
      loading: () => const Stage1ExtrasLoading(),
      error: (e, st) => Stage1ExtrasError(
        onRetry: () => ref.invalidate(phuKienProductsProvider),
      ),
      data: (products) {
        if (products.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              VN.noConfiguredExtras,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: products.map((product) {
            return ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: Text(
                '${product.name} (${formatVND(product.basePrice)})',
              ),
              onPressed: () async {
                final selection = await showDialog<CatalogExtraSelection>(
                  context: context,
                  builder: (_) => CatalogExtraPriceDialog(product: product),
                );
                if (selection == null) return;
                onAddCatalogExtra(
                  product,
                  selection.priceChipId,
                  selection.customUnitPrice,
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}