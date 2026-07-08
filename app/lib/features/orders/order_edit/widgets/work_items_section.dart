part of '../../order_edit_screen.dart';

class _WorkItemsSection extends ConsumerWidget {
  const _WorkItemsSection({required this.orderRef, required this.onAddTap});

  final String orderRef;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final workItemsAsync = ref.watch(orderWorkItemsProvider(orderRef));

    return workItemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('${VN.apiError}: $e'),
      data: (items) {
        final regularItems = items.where((i) => !i.isExtra).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...regularItems.map(
              (item) => _WorkItemEditCard(orderRef: orderRef, item: item),
            ),
            if (regularItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  VN.noWorkItems,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onAddTap,
              icon: const Icon(Icons.add, size: 16),
              label: const Text(VN.addProduct),
            ),
          ],
        );
      },
    );
  }
}
