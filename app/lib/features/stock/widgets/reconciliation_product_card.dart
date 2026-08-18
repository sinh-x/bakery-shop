// EXEMPT: This widget remains above local file-size thresholds while DG-138
// tracks broader low-risk decomposition of the tightly coupled reconciliation UI.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../providers/reconciliation_provider.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import 'reconciliation_option_editor.dart';
import 'reconciliation_option_inventory_section.dart';
import 'reconciliation_shared_widgets.dart';
import 'reconciliation_status_chip.dart';
class ReconciliationProductCard extends ConsumerStatefulWidget {
  const ReconciliationProductCard({required this.product, super.key});

  final ReconciliationDraftProduct product;

  @override
  ConsumerState<ReconciliationProductCard> createState() =>
      _ReconciliationProductCardState();
}

class _ReconciliationProductCardState
    extends ConsumerState<ReconciliationProductCard> {
  final Map<String, TextEditingController> _countedControllers = {};
  final Set<String> _expandedOptionKeys = {};
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(reconciliationProvider);
    for (final option in widget.product.options) {
      final optionKey = reconciliationOptionKey(
        widget.product.productId,
        option.normalizedPrice,
        discriminator: option.keyDiscriminator,
      );
      final counted = state.countedQtyByOption[optionKey] ?? option.defaultCountedQty;
      _countedControllers[optionKey] = TextEditingController(text: '$counted');
    }
  }

  @override
  void dispose() {
    for (final controller in _countedControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    final notifier = ref.read(reconciliationProvider.notifier);
    final visibleOptions = widget.product.options
        .where((option) => option.expectedQty != 0)
        .toList();
    final autoExpandSingleOption =
        widget.product.priceChips.isEmpty && visibleOptions.length == 1;
    var expectedTotal = 0;
    var countedTotal = 0;
    var missingTotal = 0;
    var saleTotal = 0;
    var wasteTotal = 0;
    var surplusTotal = 0;
    var hasAnyError = false;

    for (final option in widget.product.options) {
      final optionKey = reconciliationOptionKey(
        widget.product.productId,
        option.normalizedPrice,
        discriminator: option.keyDiscriminator,
      );
      final counted = state.countedQtyByOption[optionKey] ?? option.defaultCountedQty;
      final rows =
          state.saleRowsByOption[optionKey] ??
          const <ReconciliationSaleRowInput>[];
      final waste = state.wasteQtyByOption[optionKey] ?? 0;
      final wasteReason = state.wasteReasonByOption[optionKey] ?? '';
      final missing = option.expectedQty - counted;
      expectedTotal += option.expectedQty;
      countedTotal += counted;
      if (missing > 0) {
        missingTotal += missing;
      } else if (missing < 0) {
        surplusTotal += -missing;
      }
      saleTotal += rows.fold<int>(0, (sum, row) => sum + row.quantity);
      wasteTotal += waste;

      if (hasReconciliationOptionIssue(
            option: option,
            counted: counted,
            saleRows: rows,
            waste: waste,
            wasteReason: wasteReason,
          ) ||
          (state.optionErrors[optionKey] ?? '').isNotEmpty) {
        hasAnyError = true;
      }
      final rowErrors =
          state.saleRowErrorsByOption[optionKey] ??
          const <ReconciliationSaleRowError>[];
      for (final rowError in rowErrors) {
        if ((rowError.quantity ?? '').isNotEmpty ||
            (rowError.unitPrice ?? '').isNotEmpty ||
            (rowError.paymentMethod ?? '').isNotEmpty) {
          hasAnyError = true;
          break;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.product.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ReconciliationSummaryChip(label: StockLabels.tonDuKien, value: expectedTotal),
                ReconciliationSummaryChip(label: StockLabels.tonDaDem, value: countedTotal),
                ReconciliationSummaryChip(label: StockLabels.soLuongThieu, value: missingTotal),
                if (surplusTotal > 0)
                  ReconciliationSummaryChip(label: StockLabels.soLuongBu, value: surplusTotal),
                ReconciliationSummaryChip(label: StockLabels.soLuongBan, value: saleTotal),
                ReconciliationSummaryChip(label: StockLabels.soLuongHaoHut, value: wasteTotal),
                StatusChip(hasError: hasAnyError),
              ],
            ),
            if (!_isExpanded) ...[
              const SizedBox(height: 6),
              Text(
                '${StockLabels.giaCoSo}: ${widget.product.basePrice.toStringAsFixed(0)}đ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.product.options.length > 1)
                Text(
                  _collapsedOptionPriceSummary(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (_isExpanded) ...[
              const SizedBox(height: 10),
              for (final option in visibleOptions) ...[
                _buildOptionSection(
                  option,
                  state,
                  notifier,
                  canCollapse: !autoExpandSingleOption,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _optionKey(ReconciliationDraftOption option) {
    return reconciliationOptionKey(
      widget.product.productId,
      option.normalizedPrice,
      discriminator: option.keyDiscriminator,
    );
  }

  void _toggleOption(ReconciliationDraftOption option) {
    final optionKey = _optionKey(option);
    setState(() {
      if (_expandedOptionKeys.contains(optionKey)) {
        _expandedOptionKeys.remove(optionKey);
      } else {
        _expandedOptionKeys.add(optionKey);
      }
    });
  }

  Widget _buildOptionSection(
    ReconciliationDraftOption option,
    ReconciliationState state,
    ReconciliationNotifier notifier, {
    required bool canCollapse,
  }) {
    final optionKey = _optionKey(option);
    final counted = state.countedQtyByOption[optionKey] ?? option.defaultCountedQty;
    final saleRows =
        state.saleRowsByOption[optionKey] ??
        const <ReconciliationSaleRowInput>[];
    final saleQty = saleRows.fold<int>(0, (sum, row) => sum + row.quantity);
    final waste = state.wasteQtyByOption[optionKey] ?? 0;
    final wasteReason = state.wasteReasonByOption[optionKey] ?? '';
    final variance = option.expectedQty - counted - saleQty - waste;
    final surplus = state.surplusQtyFor(
      optionKey,
      option.expectedQty,
      grossAvailableQty: option.grossAvailableQty,
    );
    final saleRowErrors =
        state.saleRowErrorsByOption[optionKey] ??
        const <ReconciliationSaleRowError>[];
    final hasError =
        hasReconciliationOptionIssue(
          option: option,
          counted: counted,
          saleRows: saleRows,
          waste: waste,
          wasteReason: wasteReason,
        ) ||
        (state.optionErrors[optionKey] ?? '').isNotEmpty ||
        saleRowErrors.any((error) => error.hasError);

    return OptionInventorySection(
      optionKey: optionKey,
      option: option,
      visibleChipLabels: _visibleChipLabelsForOption(option),
      countedQty: counted,
      saleQty: saleQty,
      wasteQty: waste,
      variance: variance,
      surplus: surplus,
      hasError: hasError,
      canCollapse: canCollapse,
      isExpanded: !canCollapse || _expandedOptionKeys.contains(optionKey),
      onToggle: () => _toggleOption(option),
      child: ReconciliationOptionEditor(
        product: widget.product,
        option: option,
        countedController: _countedControllers[optionKey]!,
        syncIntController: _syncIntController,
        notifier: notifier,
      ),
    );
  }

  void _syncIntController(TextEditingController controller, int value) {
    final next = '$value';
    if (controller.text == next) {
      return;
    }
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  String _collapsedOptionPriceSummary() {
    // Count distinct options by their full option key (incl. discriminator)
    // rather than by `normalizedPrice` (DG-413 UI-4): a colliding product
    // with a base option and a chip option at the same price renders two
    // option lines, so the summary must report "2 options" even though both
    // share one normalized price.
    final optionKeys = widget.product.options
        .map(
          (option) => reconciliationOptionKey(
            widget.product.productId,
            option.normalizedPrice,
            discriminator: option.keyDiscriminator,
          ),
        )
        .toSet()
        .toList();
    if (optionKeys.isEmpty) {
      return '';
    }
    final prices = widget.product.options
        .map((option) => option.normalizedPrice.toStringAsFixed(0))
        .toSet()
        .toList();
    return '${optionKeys.length} options: ${prices.join(', ')}đ';
  }

  String _visibleChipLabelsForOption(ReconciliationDraftOption option) {
    return visibleChipLabelsForOption(widget.product, option);
  }
}