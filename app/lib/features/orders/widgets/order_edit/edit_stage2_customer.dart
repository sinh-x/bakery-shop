import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/customer.dart';
import '../../../../data/models/order_draft.dart';
import '../../../../providers/config_provider.dart';
import '../order_customer_section.dart';
import '../order_wizard.dart';
import '../section_header.dart';
import '../stage_summary_card.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Stage 2 of the order edit wizard — customer (name, phone, source).
///
/// FR6: grouped two-row source selector mirroring create's
/// `stage2_customer_info_screen.dart:143-193`. TaiTiem/walkInCustomer
/// auto-fill logic is intentionally removed to match create's simple toggle
/// pattern.
class EditStage2Customer extends ConsumerWidget {
  const EditStage2Customer({
    super.key,
    required this.selectedCustomer,
    required this.onSelectedCustomer,
    required this.onClearSelection,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.source,
    required this.onSourceChanged,
    required this.wizardSnapshot,
    required this.summaryItems,
    required this.onBack,
    required this.onContinue,
  });

  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onSelectedCustomer;
  final VoidCallback onClearSelection;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final String source;
  final ValueChanged<String> onSourceChanged;
  final OrderWizardData wizardSnapshot;
  final List<DraftOrderItem> summaryItems;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  static const _defaultSources = [
    OrdersLabels.sourceFbDoangia,
    OrdersLabels.sourceFbPageMoi,
    OrdersLabels.sourceZalo,
    OrdersLabels.sourceDienThoai,
    OrdersLabels.sourceTaiTiem,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(orderSourcesProvider);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(VN.customer),
                OrderCustomerSection(
                  selectedCustomer: selectedCustomer,
                  onSelected: onSelectedCustomer,
                  onClearSelection: onClearSelection,
                  nameCtrl: nameCtrl,
                  phoneCtrl: phoneCtrl,
                ),
                const SizedBox(height: 20),
                const SectionHeader(VN.orderSource),
                _buildSourceSelector(sourcesAsync),
                ProductSummaryCard(items: summaryItems),
                CustomerSummaryCard(
                  wizardData: wizardSnapshot,
                  source: source,
                ),
              ],
            ),
          ),
        ),
        _buildStageNavigation(),
      ],
    );
  }

  Widget _buildSourceSelector(AsyncValue<List<String>> sourcesAsync) {
    return sourcesAsync.when(
      data: (srcList) {
        final sources = srcList.isNotEmpty ? srcList : _defaultSources;
        final row1 = sources.where((s) =>
            s == OrdersLabels.sourceFbDoangia ||
            s == OrdersLabels.sourceFbPageMoi).toList();
        final row2 = sources.where((s) =>
            s == OrdersLabels.sourceZalo ||
            s == OrdersLabels.sourceDienThoai ||
            s == OrdersLabels.sourceTaiTiem).toList();
        return Column(
          children: [
            if (row1.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 8,
                  children: row1
                      .map((s) => ChoiceChip(
                            label: Text(s),
                            selected: source == s,
                            onSelected: (_) =>
                                onSourceChanged(source == s ? '' : s),
                          ))
                      .toList(),
                ),
              ),
            if (row2.isNotEmpty)
              Wrap(
                spacing: 8,
                children: row2
                    .map((s) => ChoiceChip(
                          label: Text(s),
                          selected: source == s,
                          onSelected: (_) =>
                              onSourceChanged(source == s ? '' : s),
                        ))
                    .toList(),
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
    );
  }

  Widget _buildStageNavigation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: onBack,
            child: const Text(OrdersLabels.backLabel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onContinue,
            child: const Text(OrdersLabels.continueLabel),
          ),
        ],
      ),
    );
  }
}