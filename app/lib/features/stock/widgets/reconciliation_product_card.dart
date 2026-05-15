import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/reconciliation_service.dart';
import '../../../data/providers/reconciliation_provider.dart';
import '../../../shared/labels/shared.dart';

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
  final Map<String, TextEditingController> _wasteControllers = {};
  final Map<String, TextEditingController> _wasteReasonControllers = {};
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
      final counted = state.countedQtyByOption[optionKey] ?? option.expectedQty;
      final waste = state.wasteQtyByOption[optionKey] ?? 0;
      final wasteReason = state.wasteReasonByOption[optionKey] ?? '';
      _countedControllers[optionKey] = TextEditingController(text: '$counted');
      _wasteControllers[optionKey] = TextEditingController(text: '$waste');
      _wasteReasonControllers[optionKey] = TextEditingController(text: wasteReason);
    }
  }

  @override
  void dispose() {
    for (final controller in _countedControllers.values) {
      controller.dispose();
    }
    for (final controller in _wasteControllers.values) {
      controller.dispose();
    }
    for (final controller in _wasteReasonControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    final notifier = ref.read(reconciliationProvider.notifier);
    var expectedTotal = 0;
    var countedTotal = 0;
    var missingTotal = 0;
    var saleTotal = 0;
    var wasteTotal = 0;
    var hasAnyError = false;

    for (final option in widget.product.options) {
      final optionKey = reconciliationOptionKey(
        widget.product.productId,
        option.normalizedPrice,
      );
      final counted = state.countedQtyByOption[optionKey] ?? option.expectedQty;
      final rows =
          state.saleRowsByOption[optionKey] ??
          const <ReconciliationSaleRowInput>[];
      final waste = state.wasteQtyByOption[optionKey] ?? 0;
      final missing = option.expectedQty - counted;
      expectedTotal += option.expectedQty;
      countedTotal += counted;
      if (missing > 0) {
        missingTotal += missing;
      }
      saleTotal += rows.fold<int>(0, (sum, row) => sum + row.quantity);
      wasteTotal += waste;

      if ((state.optionErrors[optionKey] ?? '').isNotEmpty) {
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
                _SummaryChip(label: VN.tonDuKien, value: expectedTotal),
                _SummaryChip(label: VN.tonDaDem, value: countedTotal),
                _SummaryChip(label: VN.soLuongThieu, value: missingTotal),
                _SummaryChip(label: VN.soLuongBan, value: saleTotal),
                _SummaryChip(label: VN.soLuongHaoHut, value: wasteTotal),
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
              for (final option
                  in widget.product.options.where((o) => o.expectedQty > 0)) ...[
                _OptionHeader(
                  option: option,
                  visibleChipLabels: _visibleChipLabelsForOption(option),
                ),
                _ReconciliationOptionEditor(
                  product: widget.product,
                  option: option,
                  countedController: _countedControllers[_optionKey(option)]!,
                  wasteController: _wasteControllers[_optionKey(option)]!,
                  wasteReasonController:
                      _wasteReasonControllers[_optionKey(option)]!,
                  syncIntController: _syncIntController,
                  notifier: notifier,
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
    return reconciliationOptionKey(widget.product.productId, option.normalizedPrice);
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
    if (option.expectedQty <= 0) {
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
    required this.wasteController,
    required this.wasteReasonController,
    required this.syncIntController,
    required this.notifier,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final TextEditingController countedController;
  final TextEditingController wasteController;
  final TextEditingController wasteReasonController;
  final void Function(TextEditingController controller, int value)
      syncIntController;
  final ReconciliationNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reconciliationProvider);
    final optionKey = reconciliationOptionKey(product.productId, option.normalizedPrice);
    final counted = state.countedQtyByOption[optionKey] ?? option.expectedQty;
    final saleRows =
        state.saleRowsByOption[optionKey] ?? const <ReconciliationSaleRowInput>[];
    final waste = state.wasteQtyByOption[optionKey] ?? 0;
    final missing = option.expectedQty - counted;
    final optionError = state.optionErrors[optionKey];
    final saleRowErrors =
        state.saleRowErrorsByOption[optionKey] ??
        const <ReconciliationSaleRowError>[];
    final showSaleEditor = missing > 0 || saleRows.isNotEmpty;

    syncIntController(countedController, counted);
    syncIntController(wasteController, waste);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QuantityStepperField(
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
        if (showSaleEditor) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () =>
                  notifier.addSaleRow(optionKey, defaultUnitPrice: option.normalizedPrice),
              icon: const Icon(Icons.add),
              label: const Text(VN.themDongBan),
            ),
          ),
          for (var rowIndex = 0; rowIndex < saleRows.length; rowIndex += 1)
            _SaleRowEditor(
              rowIndex: rowIndex,
              row: saleRows[rowIndex],
              rowError:
                  rowIndex < saleRowErrors.length ? saleRowErrors[rowIndex] : null,
              onQtyChanged: (value) =>
                  notifier.setSaleRowQty(optionKey, rowIndex, value),
              onPriceChanged: (value) =>
                  notifier.setSaleRowUnitPrice(optionKey, rowIndex, value),
              onMethodChanged: (value) =>
                  notifier.setSaleRowPaymentMethod(optionKey, rowIndex, value),
              onRemove: () => notifier.removeSaleRow(optionKey, rowIndex),
            ),
        ],
        if (missing > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${VN.soLuongThieu}: $missing',
            style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _QuantityStepperField(
            label: VN.soLuongHaoHut,
            controller: wasteController,
            onChanged: (value) => notifier.setWasteQty(optionKey, value),
            onDecrement: () {
              if (waste <= 0) {
                return;
              }
              notifier.setWasteQty(optionKey, waste - 1);
            },
            onIncrement: () => notifier.setWasteQty(optionKey, waste + 1),
          ),
          if (waste > 0) ...[
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: VN.lyDoHaoHut,
                border: OutlineInputBorder(),
              ),
              controller: wasteReasonController,
              onChanged: (value) => notifier.setWasteReasonForOption(optionKey, value),
            ),
          ],
        ],
        if (optionError != null) ...[
          const SizedBox(height: 8),
          Text(
            optionError,
            style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w600),
          ),
        ],
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
      child: Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gia ${option.normalizedPrice} - ${VN.tonDuKien}: ${option.expectedQty}',
            style: Theme.of(context).textTheme.titleSmall,
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

class _SaleRowEditor extends StatefulWidget {
  const _SaleRowEditor({
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
    _priceController = TextEditingController(text: _priceToText(widget.row.unitPrice));
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
            children: [
              Text('${VN.dongBan} ${widget.rowIndex + 1}'),
              const Spacer(),
              IconButton(
                tooltip: VN.xoa,
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
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
              widget.onPriceChanged(trimmed.isEmpty ? null : double.tryParse(trimmed));
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
              DropdownMenuItem(value: 'transfer', child: Text(VN.methodTransfer)),
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
