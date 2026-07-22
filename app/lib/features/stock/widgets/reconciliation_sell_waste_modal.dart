import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/reconciliation_provider.dart';
import '../../../shared/labels/shared.dart';
import 'reconciliation_shared_widgets.dart';

/// Opens the reconciliation sell/waste modal bottom sheet for a single product
/// option.
///
/// [optionKey] is the reconciliation option key produced by
/// [reconciliationOptionKey]. [expectedQty] and [normalizedPrice] describe the
/// option being edited. The current state values ([counted], [saleRows],
/// [waste], [wasteReason]) seed the initial display; live updates come from
/// [reconciliationProvider]. The notifier callbacks drive mutations on the
/// shared reconciliation state.
///
/// Returns `true` when the staff confirms, `false`/`null` when cancelled.
Future<bool?> showReconciliationSellWasteModal(
  BuildContext context, {
  required int productId,
  required String optionKey,
  required int expectedQty,
  required int normalizedPrice,
  required int counted,
  required List<ReconciliationSaleRowInput> saleRows,
  required int waste,
  required String wasteReason,
  required VoidCallback onAddSaleRow,
  required void Function(int rowIndex) onRemoveSaleRow,
  required void Function(int rowIndex, int value) onSetSaleRowQty,
  required void Function(int rowIndex, double? value) onSetSaleRowUnitPrice,
  required void Function(int rowIndex, String? method)
  onSetSaleRowPaymentMethod,
  required void Function(int value) onSetWasteQty,
  required void Function(String reason) onSetWasteReason,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _ReconciliationSellWasteModalContent(
      productId: productId,
      optionKey: optionKey,
      expectedQty: expectedQty,
      normalizedPrice: normalizedPrice,
      initialCounted: counted,
      initialSaleRows: saleRows,
      initialWaste: waste,
      initialWasteReason: wasteReason,
      onAddSaleRow: onAddSaleRow,
      onRemoveSaleRow: onRemoveSaleRow,
      onSetSaleRowQty: onSetSaleRowQty,
      onSetSaleRowUnitPrice: onSetSaleRowUnitPrice,
      onSetSaleRowPaymentMethod: onSetSaleRowPaymentMethod,
      onSetWasteQty: onSetWasteQty,
      onSetWasteReason: onSetWasteReason,
    ),
  );
}

class _ReconciliationSellWasteModalContent extends ConsumerStatefulWidget {
  const _ReconciliationSellWasteModalContent({
    required this.productId,
    required this.optionKey,
    required this.expectedQty,
    required this.normalizedPrice,
    required this.initialCounted,
    required this.initialSaleRows,
    required this.initialWaste,
    required this.initialWasteReason,
    required this.onAddSaleRow,
    required this.onRemoveSaleRow,
    required this.onSetSaleRowQty,
    required this.onSetSaleRowUnitPrice,
    required this.onSetSaleRowPaymentMethod,
    required this.onSetWasteQty,
    required this.onSetWasteReason,
  });

  final int productId;
  final String optionKey;
  final int expectedQty;
  final int normalizedPrice;
  final int initialCounted;
  final List<ReconciliationSaleRowInput> initialSaleRows;
  final int initialWaste;
  final String initialWasteReason;
  final VoidCallback onAddSaleRow;
  final void Function(int rowIndex) onRemoveSaleRow;
  final void Function(int rowIndex, int value) onSetSaleRowQty;
  final void Function(int rowIndex, double? value) onSetSaleRowUnitPrice;
  final void Function(int rowIndex, String? method) onSetSaleRowPaymentMethod;
  final void Function(int value) onSetWasteQty;
  final void Function(String reason) onSetWasteReason;

  @override
  ConsumerState<_ReconciliationSellWasteModalContent> createState() =>
      _ReconciliationSellWasteModalContentState();
}

class _ReconciliationSellWasteModalContentState
    extends ConsumerState<_ReconciliationSellWasteModalContent> {
  late final TextEditingController _wasteController;
  late final TextEditingController _wasteReasonController;

  @override
  void initState() {
    super.initState();
    _wasteController = TextEditingController(text: '${widget.initialWaste}');
    _wasteReasonController = TextEditingController(
      text: widget.initialWasteReason,
    );
  }

  @override
  void dispose() {
    _wasteController.dispose();
    _wasteReasonController.dispose();
    super.dispose();
  }

  void _syncWasteController(int value) {
    final next = '$value';
    if (_wasteController.text == next) {
      return;
    }
    _wasteController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _syncWasteReasonController(String value) {
    if (_wasteReasonController.text == value) {
      return;
    }
    _wasteReasonController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    final counted =
        state.countedQtyByOption[widget.optionKey] ?? widget.initialCounted;
    final saleRows =
        state.saleRowsByOption[widget.optionKey] ?? widget.initialSaleRows;
    final waste = state.wasteQtyByOption[widget.optionKey] ?? widget.initialWaste;
    final wasteReason =
        state.wasteReasonByOption[widget.optionKey] ?? widget.initialWasteReason;
    final saleRowErrors =
        state.saleRowErrorsByOption[widget.optionKey] ??
        const <ReconciliationSaleRowError>[];
    final saleQty = saleRows.fold<int>(0, (sum, row) => sum + row.quantity);
    final missing = widget.expectedQty - counted;
    final variance = widget.expectedQty - counted - saleQty - waste;

    _syncWasteController(waste);
    _syncWasteReasonController(wasteReason);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHandle(context),
              const SizedBox(height: 12),
              _buildTitle(context),
              const SizedBox(height: 12),
              _buildSummaryChips(
                context,
                expectedQty: widget.expectedQty,
                counted: counted,
                missing: missing,
                saleQty: saleQty,
                wasteQty: waste,
                variance: variance,
              ),
              const SizedBox(height: 16),
              _buildSaleSection(context, saleRows, saleRowErrors),
              const SizedBox(height: 12),
              _buildWasteSection(context, waste, wasteReason),
              const SizedBox(height: 16),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      '${VN.banHang} / ${VN.haoHutSheet}',
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSummaryChips(
    BuildContext context, {
    required int expectedQty,
    required int counted,
    required int missing,
    required int saleQty,
    required int wasteQty,
    required int variance,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ReconciliationSummaryChip(label: VN.tonDuKien, value: expectedQty),
        ReconciliationSummaryChip(label: VN.tonDaDem, value: counted),
        ReconciliationSummaryChip(
          label: VN.soLuongThieu,
          value: missing < 0 ? 0 : missing,
        ),
        ReconciliationSummaryChip(label: VN.soLuongBan, value: saleQty),
        ReconciliationSummaryChip(label: VN.soLuongHaoHut, value: wasteQty),
        ReconciliationVarianceChip(variance: variance),
      ],
    );
  }

  Widget _buildSaleSection(
    BuildContext context,
    List<ReconciliationSaleRowInput> saleRows,
    List<ReconciliationSaleRowError> saleRowErrors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: widget.onAddSaleRow,
          icon: const Icon(Icons.add),
          label: const Text(VN.themDongBan),
        ),
        for (var rowIndex = 0; rowIndex < saleRows.length; rowIndex += 1)
          ReconciliationSaleRowEditor(
            key: ValueKey('${widget.optionKey}-sale-row-$rowIndex'),
            rowIndex: rowIndex,
            row: saleRows[rowIndex],
            rowError: rowIndex < saleRowErrors.length
                ? saleRowErrors[rowIndex]
                : null,
            onQtyChanged: (value) => widget.onSetSaleRowQty(rowIndex, value),
            onPriceChanged: (value) => widget.onSetSaleRowUnitPrice(rowIndex, value),
            onMethodChanged: (value) =>
                widget.onSetSaleRowPaymentMethod(rowIndex, value),
            onRemove: () => widget.onRemoveSaleRow(rowIndex),
          ),
      ],
    );
  }

  Widget _buildWasteSection(BuildContext context, int waste, String wasteReason) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReconciliationQuantityStepperField(
          label: VN.soLuongHaoHut,
          controller: _wasteController,
          onChanged: (value) => widget.onSetWasteQty(value),
          onDecrement: () {
            if (waste <= 0) {
              return;
            }
            widget.onSetWasteQty(waste - 1);
          },
          onIncrement: () => widget.onSetWasteQty(waste + 1),
        ),
        if (waste > 0) ...[
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: VN.lyDoHaoHut,
              border: OutlineInputBorder(),
            ),
            controller: _wasteReasonController,
            onChanged: (value) => widget.onSetWasteReason(value),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(VN.dong),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(VN.xacNhan),
          ),
        ),
      ],
    );
  }
}