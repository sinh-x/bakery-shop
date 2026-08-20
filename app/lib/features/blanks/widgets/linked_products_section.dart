import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/blanks_provider.dart';
import '../../../shared/labels/blanks.dart';
import 'bom_product_tile.dart';
import 'summary_card.dart';
import 'work_item_tile.dart';

/// Reverse-lookup section: products linked via BOM and work items linked via
/// the `blank_id` FK (FR6 / AC3).
///
/// Work item rows navigate to the order detail. Extracted from
/// `blank_detail_screen.dart` per §2 of `docs/flutter-coding-standards.md`.
class LinkedProductsSection extends ConsumerWidget {
  const LinkedProductsSection({super.key, required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(blankProductsProvider(blankId));
    return SummaryCard(
      title: BlanksLabels.sectionLinkedProducts,
      icon: Icons.link_outlined,
      child: productsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => const Text(BlanksLabels.emptyData),
        data: (p) {
          final hasBom = p.bomProducts.isNotEmpty;
          final hasItems = p.workItems.isNotEmpty;
          if (!hasBom && !hasItems) {
            return const Text(BlanksLabels.linkedEmpty);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasBom) ...[
                Text(
                  BlanksLabels.linkedBomProducts,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                for (final b in p.bomProducts) BomProductTile(product: b),
                if (hasItems) const SizedBox(height: 12),
              ],
              if (hasItems) ...[
                Text(
                  BlanksLabels.linkedWorkItems,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                for (final w in p.workItems) WorkItemTile(item: w),
              ],
            ],
          );
        },
      ),
    );
  }
}