part of '../../order_edit_screen.dart';

class _EditExtrasSection extends ConsumerWidget {
  const _EditExtrasSection({required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workItemsAsync = ref.watch(orderWorkItemsProvider(orderRef));
    final extrasAsync = ref.watch(phuKienProductsProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(orderWorkItemsProvider(orderRef).notifier);

    return workItemsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (workItems) {
        final extras = workItems.where((i) => i.isExtra).toList();

        return extrasAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, st) => const SizedBox.shrink(),
          data: (products) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(VN.extras),
                if (extras.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Chưa có phụ kiện',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                else
                  ...extras.map(
                    (extra) => _ExtraEditRow(
                      item: extra,
                      onIncrement: () async {
                        await notifier.edit(
                          extra.id,
                          quantity: extra.quantity + 1,
                        );
                      },
                      onDecrement: () async {
                        if (extra.quantity > 1) {
                          await notifier.edit(
                            extra.id,
                            quantity: extra.quantity - 1,
                          );
                        } else {
                          await notifier.remove(extra.id);
                        }
                      },
                      onToggleGift: () async {
                        await notifier.edit(extra.id, isGift: !extra.isGift);
                      },
                      onRemove: () async {
                        await notifier.remove(extra.id);
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                if (products.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: products.map((product) {
                      return ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text(
                          '${product.name} (${formatVND(product.basePrice)})',
                        ),
                        onPressed: () async {
                          final selection = await showDialog<
                            _EditCatalogExtraSelection
                          >(
                            context: context,
                            builder: (_) =>
                                _EditCatalogExtraPriceDialog(product: product),
                          );
                          if (selection == null) return;

                          final unitPrice =
                              selection.customUnitPrice ?? product.basePrice;
                          final existing = extras
                              .where(
                                (e) =>
                                    e.productId == product.id.toString() &&
                                    !e.isGift &&
                                    e.unitPrice == unitPrice,
                              )
                              .firstOrNull;
                          if (existing != null) {
                            await notifier.edit(
                              existing.id,
                              quantity: existing.quantity + 1,
                            );
                          } else {
                            await notifier.add(
                              productName: product.name,
                              productId: product.id.toString(),
                              unitPrice: unitPrice,
                              isExtra: true,
                              isGift: false,
                              priceChipId: selection.priceChipId,
                            );
                          }
                        },
                      );
                    }).toList(),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _EditCatalogExtraSelection {
  const _EditCatalogExtraSelection({this.priceChipId, this.customUnitPrice});

  final int? priceChipId;
  final double? customUnitPrice;
}

class _EditCatalogExtraPriceDialog extends StatefulWidget {
  const _EditCatalogExtraPriceDialog({required this.product});

  final Product product;

  @override
  State<_EditCatalogExtraPriceDialog> createState() =>
      _EditCatalogExtraPriceDialogState();
}

class _EditCatalogExtraPriceDialogState
    extends State<_EditCatalogExtraPriceDialog> {
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
                _EditCatalogExtraSelection(customUnitPrice: manualPrice),
              );
              return;
            }

            final selected = options.firstWhere((o) => o.$1 == _selectedOptionId);
            if (selected.$4 == null) {
              Navigator.pop(
                context,
                const _EditCatalogExtraSelection(customUnitPrice: null),
              );
            } else {
              Navigator.pop(
                context,
                _EditCatalogExtraSelection(priceChipId: selected.$4),
              );
            }
          },
          child: const Text(VN.xacNhan),
        ),
      ],
    );
  }
}

class _ExtraEditRow extends StatelessWidget {
  const _ExtraEditRow({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleGift,
    required this.onRemove,
  });

  final WorkItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onToggleGift;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggleGift,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: item.isGift
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: item.isGift ? Colors.green : Colors.grey.shade300,
                ),
              ),
              child: Text(
                item.isGift ? VN.giftBadge : VN.paymentFee,
                style: TextStyle(
                  fontSize: 10,
                  color: item.isGift ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${item.productName} (${formatVND(item.unitPrice)})',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDecrement,
          ),
          Text('${item.quantity}', style: theme.textTheme.bodyMedium),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onIncrement,
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: theme.colorScheme.error),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
