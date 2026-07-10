import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/pos_provider.dart';
import '../../../shared/labels/shared.dart';
import '../utils/pos_cart_item_display.dart';

class PosCheckoutCartItemTile extends ConsumerWidget {
  const PosCheckoutCartItemTile({super.key, required this.item});

  final PosCartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey('${item.lineKey}-${item.isGift}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                title: const Text(VN.removeFromCartTitle),
                content: Text(
                  '${VN.clear} "${item.product.name}" ${VN.removedFromCartSuffix}?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: const Text(VN.huy),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogCtx, true),
                    child: const Text(VN.xoa),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) {
        ref.read(posCartProvider.notifier).removeItemByLineKey(item.lineKey);
        showTopSnackBar(
          context,
          '${VN.removedFromCartPrefix} ${item.product.name} ${VN.removedFromCartSuffix}',
        );
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ListTile(
          leading: item.isGift
              ? const Chip(label: Text('🎁'))
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cake,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                posCartItemDisplayName(item),
                style: item.isGift
                    ? theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      )
                    : null,
              ),
              if (!item.isGift && item.useInventory)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _UseInventoryBadge(useInventory: item.useInventory),
                ),
            ],
          ),
          subtitle: item.isGift ? null : Text(formatVND(item.unitPrice)),
          trailing: item.isGift
              ? Icon(Icons.chevron_left, color: theme.colorScheme.outline)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      tooltip: VN.decreaseQuantity,
                      onPressed: () {
                        ref
                            .read(posCartProvider.notifier)
                            .updateQuantityByLineKey(
                              item.lineKey,
                              item.quantity - 1,
                            );
                      },
                    ),
                    Text(
                      '${item.quantity}',
                      style: theme.textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      tooltip: VN.increaseQuantity,
                      onPressed: () {
                        ref
                            .read(posCartProvider.notifier)
                            .updateQuantityByLineKey(
                              item.lineKey,
                              item.quantity + 1,
                            );
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _UseInventoryBadge extends StatelessWidget {
  const _UseInventoryBadge({required this.useInventory});

  final bool useInventory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: useInventory
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        VN.useInventory,
        style: theme.textTheme.labelSmall?.copyWith(
          color: useInventory
              ? theme.colorScheme.onTertiaryContainer
              : theme.colorScheme.outline,
          fontSize: 10,
        ),
      ),
    );
  }
}
