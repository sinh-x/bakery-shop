// EXEMPT: This widget remains above local file-size thresholds while DG-138
// tracks broader low-risk decomposition of the tightly coupled reconciliation UI.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../data/providers/reconciliation_provider.dart';
import '../../../shared/labels/shared.dart';
import 'reconciliation_sell_waste_modal.dart';
import 'reconciliation_shared_widgets.dart';
import 'reconciliation_surplus_indicator.dart';
import 'reconciliation_variance_indicator.dart';

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
                ReconciliationSummaryChip(label: VN.tonDuKien, value: expectedTotal),
                ReconciliationSummaryChip(label: VN.tonDaDem, value: countedTotal),
                ReconciliationSummaryChip(label: VN.soLuongThieu, value: missingTotal),
                if (surplusTotal > 0)
                  ReconciliationSummaryChip(label: VN.soLuongBu, value: surplusTotal),
                ReconciliationSummaryChip(label: VN.soLuongBan, value: saleTotal),
                ReconciliationSummaryChip(label: VN.soLuongHaoHut, value: wasteTotal),
                _StatusChip(hasError: hasAnyError),
              ],
            ),
            if (!_isExpanded) ...[
              const SizedBox(height: 6),
              Text(
                '${VN.giaCoSo}: ${widget.product.basePrice.toStringAsFixed(0)}đ',
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

    return _OptionInventorySection(
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
      child: _ReconciliationOptionEditor(
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
    final prices = widget.product.options
        .map((option) => option.normalizedPrice.toStringAsFixed(0))
        .toSet()
        .toList();
    if (prices.isEmpty) {
      return '';
    }
    return '${prices.length} options: ${prices.join(', ')}đ';
  }

  String _visibleChipLabelsForOption(ReconciliationDraftOption option) {
    if (option.expectedQty == 0) {
      return '';
    }

    if (option.sourceChipIds.isNotEmpty) {
      final sourceChipIds = option.sourceChipIds.toSet();
      return widget.product.priceChips
          .where((chip) => sourceChipIds.contains(chip.id))
          .map((chip) => chip.label)
          .join(', ');
    }

    return option.sourceChipLabels.join(', ');
  }
}

class _ReconciliationOptionEditor extends ConsumerWidget {
  const _ReconciliationOptionEditor({
    required this.product,
    required this.option,
    required this.countedController,
    required this.syncIntController,
    required this.notifier,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final TextEditingController countedController;
  final void Function(TextEditingController controller, int value)
  syncIntController;
  final ReconciliationNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reconciliationProvider);
    final optionKey = reconciliationOptionKey(
      product.productId,
      option.normalizedPrice,
    );
    final counted = state.countedQtyByOption[optionKey] ?? option.defaultCountedQty;
    final saleRows =
        state.saleRowsByOption[optionKey] ??
        const <ReconciliationSaleRowInput>[];
    final waste = state.wasteQtyByOption[optionKey] ?? 0;
    final wasteReason = state.wasteReasonByOption[optionKey] ?? '';
    final saleQty = saleRows.fold<int>(0, (sum, row) => sum + row.quantity);
    final variance = option.expectedQty - counted - saleQty - waste;
    final surplus = state.surplusQtyFor(
      optionKey,
      option.expectedQty,
      grossAvailableQty: option.grossAvailableQty,
    );
    final optionError = state.optionErrors[optionKey];

    syncIntController(countedController, counted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReconciliationQuantityStepperField(
          label: VN.tonDaDem,
          controller: countedController,
          onChanged: (value) => notifier.setCountedQty(optionKey, value),
          onDecrement: () {
            if (counted <= 0) {
              return;
            }
            notifier.setCountedQty(optionKey, counted - 1);
          },
          onIncrement: () => notifier.setCountedQty(optionKey, counted + 1),
        ),
        if (surplus > 0) ...[
          const SizedBox(height: 8),
          ReconciliationSurplusIndicator(surplus: surplus),
          const SizedBox(height: 4),
          Text(
            VN.nhapBuHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.teal[700],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => showReconciliationSaleModal(
                context,
                product: product,
                option: option,
                optionKey: optionKey,
                counted: counted,
                saleRows: saleRows,
                waste: waste,
                wasteReason: wasteReason,
                notifier: notifier,
              ),
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text(VN.banHang),
            ),
            OutlinedButton.icon(
              onPressed: () => showReconciliationWasteModal(
                context,
                product: product,
                option: option,
                optionKey: optionKey,
                counted: counted,
                saleRows: saleRows,
                waste: waste,
                wasteReason: wasteReason,
                notifier: notifier,
              ),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text(VN.haoHutSheet),
            ),
            ReconciliationVarianceIndicator(variance: variance),
          ],
        ),
        if (saleRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InlineSaleRowList(
            product: product,
            option: option,
            optionKey: optionKey,
            counted: counted,
            saleRows: saleRows,
            waste: waste,
            wasteReason: wasteReason,
            notifier: notifier,
          ),
        ],
        if (waste > 0 || wasteReason.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InlineWasteItem(
            product: product,
            option: option,
            optionKey: optionKey,
            counted: counted,
            saleRows: saleRows,
            waste: waste,
            wasteReason: wasteReason,
            notifier: notifier,
          ),
        ],
        if (optionError != null) ...[
          const SizedBox(height: 8),
          Text(
            optionError,
            style: TextStyle(
              color: Colors.red[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.hasError});

  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final color = hasError ? Colors.red[700]! : Colors.green[700]!;
    final text = hasError ? VN.trangThaiCoLoi : VN.trangThaiOn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${VN.trangThai}: $text',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

class _OptionHeader extends StatelessWidget {
  const _OptionHeader({required this.option, required this.visibleChipLabels});

  final ReconciliationDraftOption option;
  final String visibleChipLabels;

  @override
  Widget build(BuildContext context) {
    final priceLineStyle = Theme.of(context).textTheme.titleSmall;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Giá ${formatVND(option.normalizedPrice.toDouble())} - ${VN.tonDuKien}: ${option.expectedQty}',
            style: priceLineStyle?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: (priceLineStyle.fontSize ?? 14) + 1,
            ),
          ),
          if (visibleChipLabels.isNotEmpty)
            Text(
              '${VN.nhanChip}: $visibleChipLabels',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _OptionInventorySection extends StatelessWidget {
  const _OptionInventorySection({
    required this.optionKey,
    required this.option,
    required this.visibleChipLabels,
    required this.countedQty,
    required this.saleQty,
    required this.wasteQty,
    required this.variance,
    required this.surplus,
    required this.hasError,
    required this.canCollapse,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
  });

  final String optionKey;
  final ReconciliationDraftOption option;
  final String visibleChipLabels;
  final int countedQty;
  final int saleQty;
  final int wasteQty;
  final int variance;
  final int surplus;
  final bool hasError;
  final bool canCollapse;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canCollapse)
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _OptionInventoryHeader(
                option: option,
                visibleChipLabels: visibleChipLabels,
                optionKey: optionKey,
                countedQty: countedQty,
                saleQty: saleQty,
                wasteQty: wasteQty,
                variance: variance,
                surplus: surplus,
                hasError: hasError,
                trailing: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _OptionInventoryHeader(
              option: option,
              visibleChipLabels: visibleChipLabels,
              optionKey: optionKey,
              countedQty: countedQty,
              saleQty: saleQty,
              wasteQty: wasteQty,
              variance: variance,
              surplus: surplus,
              hasError: hasError,
            ),
          ),
        if (isExpanded) ...[const SizedBox(height: 6), child],
      ],
    );
  }
}

class _OptionInventoryHeader extends StatelessWidget {
  const _OptionInventoryHeader({
    required this.option,
    required this.visibleChipLabels,
    required this.optionKey,
    required this.countedQty,
    required this.saleQty,
    required this.wasteQty,
    required this.variance,
    required this.surplus,
    required this.hasError,
    this.trailing,
  });

  final ReconciliationDraftOption option;
  final String visibleChipLabels;
  final String optionKey;
  final int countedQty;
  final int saleQty;
  final int wasteQty;
  final int variance;
  final int surplus;
  final bool hasError;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OptionHeader(
                option: option,
                visibleChipLabels: visibleChipLabels,
              ),
              Wrap(
                key: ValueKey('reconciliation-option-summary-$optionKey'),
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ReconciliationSummaryChip(label: VN.tonDaDem, value: countedQty),
                  ReconciliationSummaryChip(label: VN.soLuongBan, value: saleQty),
                  ReconciliationSummaryChip(label: VN.soLuongHaoHut, value: wasteQty),
                  ReconciliationVarianceIndicator(variance: variance),
                  if (surplus > 0)
                    ReconciliationSurplusIndicator(surplus: surplus),
                  _StatusChip(hasError: hasError),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class _InlineSaleRowList extends StatelessWidget {
  const _InlineSaleRowList({
    required this.product,
    required this.option,
    required this.optionKey,
    required this.counted,
    required this.saleRows,
    required this.waste,
    required this.wasteReason,
    required this.notifier,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final String optionKey;
  final int counted;
  final List<ReconciliationSaleRowInput> saleRows;
  final int waste;
  final String wasteReason;
  final ReconciliationNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var rowIndex = 0; rowIndex < saleRows.length; rowIndex += 1)
          _InlineSaleRowItem(
            key: ValueKey('$optionKey-inline-sale-row-$rowIndex'),
            product: product,
            option: option,
            optionKey: optionKey,
            counted: counted,
            saleRows: saleRows,
            waste: waste,
            wasteReason: wasteReason,
            notifier: notifier,
            rowIndex: rowIndex,
            row: saleRows[rowIndex],
          ),
      ],
    );
  }
}

class _InlineSaleRowItem extends StatelessWidget {
  const _InlineSaleRowItem({
    required this.product,
    required this.option,
    required this.optionKey,
    required this.counted,
    required this.saleRows,
    required this.waste,
    required this.wasteReason,
    required this.notifier,
    required this.rowIndex,
    required this.row,
    super.key,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final String optionKey;
  final int counted;
  final List<ReconciliationSaleRowInput> saleRows;
  final int waste;
  final String wasteReason;
  final ReconciliationNotifier notifier;
  final int rowIndex;
  final ReconciliationSaleRowInput row;

  @override
  Widget build(BuildContext context) {
    final priceText = row.unitPrice == null
        ? '-'
        : formatVND(row.unitPrice!.toDouble());
    final methodText = row.paymentMethod == null || row.paymentMethod!.isEmpty
        ? '-'
        : paymentMethodLabel(row.paymentMethod!);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${VN.dongBan} ${rowIndex + 1}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${VN.soLuongBan}: ${row.quantity} - $priceText - $methodText',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: VN.sua,
            onPressed: () => showReconciliationSaleModal(
              context,
              product: product,
              option: option,
              optionKey: optionKey,
              counted: counted,
              saleRows: saleRows,
              waste: waste,
              wasteReason: wasteReason,
              notifier: notifier,
              editingRowIndex: rowIndex,
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: VN.xoa,
            onPressed: () => notifier.removeSaleRow(optionKey, rowIndex),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _InlineWasteItem extends StatelessWidget {
  const _InlineWasteItem({
    required this.product,
    required this.option,
    required this.optionKey,
    required this.counted,
    required this.saleRows,
    required this.waste,
    required this.wasteReason,
    required this.notifier,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final String optionKey;
  final int counted;
  final List<ReconciliationSaleRowInput> saleRows;
  final int waste;
  final String wasteReason;
  final ReconciliationNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final reasonText = wasteReason.isEmpty ? '-' : wasteReason;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  VN.haoHutSheet,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${VN.soLuongHaoHut}: $waste - ${VN.lyDoHaoHut}: $reasonText',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: VN.sua,
            onPressed: () => showReconciliationWasteModal(
              context,
              product: product,
              option: option,
              optionKey: optionKey,
              counted: counted,
              saleRows: saleRows,
              waste: waste,
              wasteReason: wasteReason,
              notifier: notifier,
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: VN.xoa,
            onPressed: () {
              notifier.setWasteQty(optionKey, 0);
              notifier.setWasteReasonForOption(optionKey, '');
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
