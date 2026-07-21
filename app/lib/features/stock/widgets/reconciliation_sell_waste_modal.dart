import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/reconciliation_provider.dart';
import '../../../shared/labels/shared.dart';

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

  @override
  void initState() {
    super.initState();
    _wasteController = TextEditingController(text: '${widget.initialWaste}');
  }

  @override
  void dispose() {
    _wasteController.dispose();
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
        _SummaryChip(label: VN.tonDuKien, value: expectedQty),
        _SummaryChip(label: VN.tonDaDem, value: counted),
        _SummaryChip(label: VN.soLuongThieu, value: missing < 0 ? 0 : missing),
        _SummaryChip(label: VN.soLuongBan, value: saleQty),
        _SummaryChip(label: VN.soLuongHaoHut, value: wasteQty),
        _VarianceChip(variance: variance),
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
          _SaleRowEditor(
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
        _QuantityStepperField(
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
            controller: TextEditingController(text: wasteReason),
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
            child: const Text(VN.huy),
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

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _VarianceChip extends StatelessWidget {
  const _VarianceChip({required this.variance});

  final int variance;

  @override
  Widget build(BuildContext context) {
    final color = variance == 0 ? Colors.green[700]! : Colors.red[700]!;
    final text =
        variance == 0
            ? '0'
            : (variance > 0 ? '+$variance' : '$variance');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${VN.soLuongChenhLech}: $text',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

class _SaleRowEditor extends StatefulWidget {
  const _SaleRowEditor({
    super.key,
    required this.rowIndex,
    required this.row,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onMethodChanged,
    required this.onRemove,
    this.rowError,
  });

  final int rowIndex;
  final ReconciliationSaleRowInput row;
  final ReconciliationSaleRowError? rowError;
  final ValueChanged<int> onQtyChanged;
  final ValueChanged<double?> onPriceChanged;
  final ValueChanged<String?> onMethodChanged;
  final VoidCallback onRemove;

  @override
  State<_SaleRowEditor> createState() => _SaleRowEditorState();
}

class _SaleRowEditorState extends State<_SaleRowEditor> {
  late TextEditingController _qtyController;
  late TextEditingController _priceController;
  final FocusNode _priceFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: '${widget.row.quantity}');
    _priceController = TextEditingController(
      text: _priceToText(widget.row.unitPrice),
    );
  }

  @override
  void didUpdateWidget(covariant _SaleRowEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextQty = '${widget.row.quantity}';
    if (_qtyController.text != nextQty) {
      _qtyController.value = TextEditingValue(
        text: nextQty,
        selection: TextSelection.collapsed(offset: nextQty.length),
      );
    }

    final nextPrice = _priceToText(widget.row.unitPrice);
    if (!_priceFocusNode.hasFocus && _priceController.text != nextPrice) {
      _priceController.value = TextEditingValue(
        text: nextPrice,
        selection: TextSelection.collapsed(offset: nextPrice.length),
      );
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quantity = widget.row.quantity;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${VN.dongBan} ${widget.rowIndex + 1}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: VN.xoa,
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _QuantityStepperField(
            label: VN.soLuongBan,
            controller: _qtyController,
            errorText: widget.rowError?.quantity,
            onChanged: widget.onQtyChanged,
            onDecrement: () {
              if (quantity <= 0) {
                return;
              }
              widget.onQtyChanged(quantity - 1);
            },
            onIncrement: () => widget.onQtyChanged(quantity + 1),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('reconciliation-unit-price-field'),
            controller: _priceController,
            focusNode: _priceFocusNode,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final trimmed = value.trim();
              widget.onPriceChanged(
                trimmed.isEmpty ? null : double.tryParse(trimmed),
              );
            },
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: VN.donGiaNhapTay,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: widget.rowError?.unitPrice,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: widget.row.paymentMethod,
            decoration: InputDecoration(
              labelText: VN.phuongThucThanhToan,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: widget.rowError?.paymentMethod,
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text(VN.methodCash)),
              DropdownMenuItem(
                value: 'transfer',
                child: Text(VN.methodTransfer),
              ),
            ],
            onChanged: widget.onMethodChanged,
          ),
        ],
      ),
    );
  }

  String _priceToText(double? price) {
    if (price == null) {
      return '';
    }
    return price == price.roundToDouble()
        ? price.toInt().toString()
        : price.toString();
  }
}

class _QuantityStepperField extends StatelessWidget {
  const _QuantityStepperField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onDecrement,
    required this.onIncrement,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<int> onChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: onDecrement,
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: VN.giam,
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
            onChanged: (value) => onChanged(int.tryParse(value) ?? 0),
          ),
        ),
        IconButton(
          onPressed: onIncrement,
          icon: const Icon(Icons.add_circle_outline),
          tooltip: VN.tang,
        ),
      ],
    );
  }
}