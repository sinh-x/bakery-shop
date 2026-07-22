import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/providers/reconciliation_provider.dart';
import '../../../shared/labels/shared.dart';

class ReconciliationSummaryChip extends StatelessWidget {
  const ReconciliationSummaryChip({
    required this.label,
    required this.value,
    super.key,
  });

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

class ReconciliationQuantityStepperField extends StatelessWidget {
  const ReconciliationQuantityStepperField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onDecrement,
    required this.onIncrement,
    this.errorText,
    super.key,
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

class ReconciliationVarianceChip extends StatelessWidget {
  const ReconciliationVarianceChip({required this.variance, super.key});

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

class ReconciliationSaleRowEditor extends StatefulWidget {
  const ReconciliationSaleRowEditor({
    required this.rowIndex,
    required this.row,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onMethodChanged,
    required this.onRemove,
    this.rowError,
    super.key,
  });

  final int rowIndex;
  final ReconciliationSaleRowInput row;
  final ReconciliationSaleRowError? rowError;
  final ValueChanged<int> onQtyChanged;
  final ValueChanged<double?> onPriceChanged;
  final ValueChanged<String?> onMethodChanged;
  final VoidCallback onRemove;

  @override
  State<ReconciliationSaleRowEditor> createState() =>
      _ReconciliationSaleRowEditorState();
}

class _ReconciliationSaleRowEditorState
    extends State<ReconciliationSaleRowEditor> {
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
  void didUpdateWidget(covariant ReconciliationSaleRowEditor oldWidget) {
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
          ReconciliationQuantityStepperField(
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