import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/order_providers.dart';
import '../../../../data/providers/products_provider.dart';
import '../../widgets/section_header.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'edit_catalog_extra_price_dialog.dart';
import 'edit_catalog_extra_selection.dart';
import 'extra_edit_row.dart';

class EditExtrasSection extends ConsumerWidget {
  const EditExtrasSection({super.key, required this.orderRef});

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
                const SectionHeader(OrdersLabels.extras),
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
                    (extra) => ExtraEditRow(
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
                            EditCatalogExtraSelection
                          >(
                            context: context,
                            builder: (_) =>
                                EditCatalogExtraPriceDialog(product: product),
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