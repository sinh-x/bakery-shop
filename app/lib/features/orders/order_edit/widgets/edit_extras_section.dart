part of '../../order_edit_screen.dart';

class _EditExtrasSection extends ConsumerWidget {
  const _EditExtrasSection({required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workItemsAsync = ref.watch(orderWorkItemsProvider(orderRef));
    final extrasAsync = ref.watch(orderExtrasProvider);
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
          data: (extraValues) {
            final presets = <(String, double)>[];
            for (final v in extraValues) {
              final parts = v.split('|');
              if (parts.length == 2) {
                final name = parts[0].trim();
                final price = double.tryParse(parts[1].trim()) ?? 0;
                presets.add((name, price));
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(VN.extras),
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
                if (presets.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((preset) {
                      final (name, price) = preset;
                      return ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text('$name (${formatVND(price)})'),
                        onPressed: () async {
                          final existing = extras
                              .where((e) => e.productName == name && !e.isGift)
                              .firstOrNull;
                          if (existing != null) {
                            await notifier.edit(
                              existing.id,
                              quantity: existing.quantity + 1,
                            );
                          } else {
                            await notifier.add(
                              productName: name,
                              unitPrice: price,
                              isExtra: true,
                              isGift: false,
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
