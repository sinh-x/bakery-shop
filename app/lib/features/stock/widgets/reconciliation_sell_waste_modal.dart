import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/reconciliation_models.dart';
import '../../../data/providers/reconciliation_provider.dart';
import '../../../shared/labels/shared.dart';
import 'reconciliation_shared_widgets.dart';

/// Opens the reconciliation sale modal bottom sheet for a single product
/// option.
///
/// The modal shows summary chips (expected, counted, missing, sale, waste,
/// variance), the product name + option price header, existing sale rows for
/// reference, the variance indicator, and a single local-state sale row form
/// (quantity, unit price, payment method). Submitting calls [onAddSaleRow]
/// with the entered values, which adds one line item.
///
/// Returns `true` when the staff confirms, `false`/`null` when cancelled.
Future<bool?> showReconciliationSaleModal(
  BuildContext context, {
  required ReconciliationDraftProduct product,
  required ReconciliationDraftOption option,
  required String optionKey,
  required int counted,
  required List<ReconciliationSaleRowInput> saleRows,
  required int waste,
  required String wasteReason,
  required ReconciliationNotifier notifier,
  int? editingRowIndex,
}) {
  final editingRow =
      editingRowIndex == null || editingRowIndex >= saleRows.length
          ? null
          : saleRows[editingRowIndex];
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _ReconciliationSaleModalContent(
      product: product,
      option: option,
      optionKey: optionKey,
      initialCounted: counted,
      initialSaleRows: saleRows,
      initialWaste: waste,
      initialWasteReason: wasteReason,
      notifier: notifier,
      editingRowIndex: editingRowIndex,
      initialQty: editingRow?.quantity ?? 0,
      initialUnitPrice: editingRow?.unitPrice ?? option.normalizedPrice.toDouble(),
      initialPaymentMethod: editingRow?.paymentMethod,
    ),
  );
}

/// Opens the reconciliation waste modal bottom sheet for a single product
/// option.
///
/// The modal shows summary chips (expected, counted, missing, sale, waste,
/// variance), the product name + option price header, existing waste for
/// reference, the variance indicator, and a single local-state waste entry
/// form (quantity, reason — reason shown only when qty > 0). Submitting calls
/// [notifier.setWasteQty] and [notifier.setWasteReasonForOption].
///
/// Returns `true` when the staff confirms, `false`/`null` when cancelled.
Future<bool?> showReconciliationWasteModal(
  BuildContext context, {
  required ReconciliationDraftProduct product,
  required ReconciliationDraftOption option,
  required String optionKey,
  required int counted,
  required List<ReconciliationSaleRowInput> saleRows,
  required int waste,
  required String wasteReason,
  required ReconciliationNotifier notifier,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _ReconciliationWasteModalContent(
      product: product,
      option: option,
      optionKey: optionKey,
      initialCounted: counted,
      initialSaleRows: saleRows,
      initialWaste: waste,
      initialWasteReason: wasteReason,
      notifier: notifier,
    ),
  );
}

class _ReconciliationSaleModalContent extends ConsumerStatefulWidget {
  const _ReconciliationSaleModalContent({
    required this.product,
    required this.option,
    required this.optionKey,
    required this.initialCounted,
    required this.initialSaleRows,
    required this.initialWaste,
    required this.initialWasteReason,
    required this.notifier,
    this.editingRowIndex,
    this.initialQty = 0,
    this.initialUnitPrice,
    this.initialPaymentMethod,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final String optionKey;
  final int initialCounted;
  final List<ReconciliationSaleRowInput> initialSaleRows;
  final int initialWaste;
  final String initialWasteReason;
  final ReconciliationNotifier notifier;
  final int? editingRowIndex;
  final int initialQty;
  final double? initialUnitPrice;
  final String? initialPaymentMethod;

  @override
  ConsumerState<_ReconciliationSaleModalContent> createState() =>
      _ReconciliationSaleModalContentState();
}

class _ReconciliationSaleModalContentState
    extends ConsumerState<_ReconciliationSaleModalContent> {
  late final TextEditingController _qtyController;
  late final TextEditingController _priceController;
  final FocusNode _priceFocusNode = FocusNode();
  String? _paymentMethod;
  bool _paymentMethodError = false;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: '${widget.initialQty}');
    _priceController = TextEditingController(
      text: reconciliationPriceToText(widget.initialUnitPrice),
    );
    _paymentMethod = widget.initialPaymentMethod ?? kPaymentMethodCash;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  int get _qty => int.tryParse(_qtyController.text) ?? 0;

  double? get _unitPrice {
    final trimmed = _priceController.text.trim();
    return trimmed.isEmpty ? null : double.tryParse(trimmed);
  }

  void _submit() {
    final editingIndex = widget.editingRowIndex;
    if (editingIndex == null) {
      if (_qty <= 0) {
        Navigator.of(context).pop(true);
        return;
      }
      if (_qty > 0 && _paymentMethod == null) {
        setState(() => _paymentMethodError = true);
        return;
      }
      widget.notifier.addSaleRow(
        widget.optionKey,
        defaultUnitPrice: widget.option.normalizedPrice,
      );
      final rowIndex =
          (ref.read(reconciliationProvider).saleRowsByOption[widget.optionKey] ??
                  const <ReconciliationSaleRowInput>[])
              .length -
          1;
      if (rowIndex >= 0) {
        widget.notifier.setSaleRowQty(widget.optionKey, rowIndex, _qty);
        widget.notifier.setSaleRowUnitPrice(
          widget.optionKey,
          rowIndex,
          _unitPrice,
        );
        widget.notifier.setSaleRowPaymentMethod(
          widget.optionKey,
          rowIndex,
          _paymentMethod,
        );
      }
    } else {
      widget.notifier.setSaleRowQty(widget.optionKey, editingIndex, _qty);
      widget.notifier.setSaleRowUnitPrice(
        widget.optionKey,
        editingIndex,
        _unitPrice,
      );
      widget.notifier.setSaleRowPaymentMethod(
        widget.optionKey,
        editingIndex,
        _paymentMethod,
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    final counted =
        state.countedQtyByOption[widget.optionKey] ?? widget.initialCounted;
    final saleRows =
        state.saleRowsByOption[widget.optionKey] ?? widget.initialSaleRows;
    final waste =
        state.wasteQtyByOption[widget.optionKey] ?? widget.initialWaste;
    final saleQty = saleRows.fold<int>(0, (sum, row) => sum + row.quantity);
    final missing = widget.option.expectedQty - counted;
    final variance = widget.option.expectedQty - counted - saleQty - waste;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildReconciliationModalHandle(context),
              const SizedBox(height: 12),
              _buildTitle(context),
              const SizedBox(height: 12),
              _buildSummaryChips(
                context,
                expectedQty: widget.option.expectedQty,
                counted: counted,
                missing: missing,
                saleQty: saleQty,
                wasteQty: waste,
                variance: variance,
              ),
              const SizedBox(height: 12),
              buildReconciliationProductHeader(
                context,
                product: widget.product,
                option: widget.option,
              ),
              const SizedBox(height: 16),
              if (widget.editingRowIndex == null)
                _buildExistingSaleRows(context, saleRows),
              const SizedBox(height: 16),
              _buildSaleForm(context),
              const SizedBox(height: 16),
              buildReconciliationModalActions(context, onSubmit: _submit),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      widget.editingRowIndex == null ? VN.banHang : '${VN.banHang} - ${VN.sua}',
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildExistingSaleRows(
    BuildContext context,
    List<ReconciliationSaleRowInput> saleRows,
  ) {
    if (saleRows.isEmpty) {
      return const SizedBox.shrink();
    }
    if (widget.editingRowIndex == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var rowIndex = 0; rowIndex < saleRows.length; rowIndex += 1)
            Container(
              key: ValueKey('${widget.optionKey}-sale-row-$rowIndex'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(8),
              ),
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
                  const SizedBox(height: 4),
                  Text(
                    '${VN.soLuongBan}: ${saleRows[rowIndex].quantity}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '${VN.donGiaNhapTay}: ${formatVND(saleRows[rowIndex].unitPrice?.toDouble() ?? 0)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '${VN.phuongThucThanhToan}: ${saleRows[rowIndex].paymentMethod == null ? "" : paymentMethodLabel(saleRows[rowIndex].paymentMethod!)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var rowIndex = 0; rowIndex < saleRows.length; rowIndex += 1)
          ReconciliationSaleRowEditor(
            key: ValueKey('${widget.optionKey}-sale-row-$rowIndex'),
            rowIndex: rowIndex,
            row: saleRows[rowIndex],
            onQtyChanged: (value) =>
                widget.notifier.setSaleRowQty(widget.optionKey, rowIndex, value),
            onPriceChanged: (value) => widget.notifier.setSaleRowUnitPrice(
              widget.optionKey,
              rowIndex,
              value,
            ),
            onMethodChanged: (value) => widget.notifier.setSaleRowPaymentMethod(
              widget.optionKey,
              rowIndex,
              value,
            ),
            onRemove: () =>
                widget.notifier.removeSaleRow(widget.optionKey, rowIndex),
          ),
      ],
    );
  }

  Widget _buildSaleForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReconciliationQuantityStepperField(
            label: VN.soLuongBan,
            controller: _qtyController,
            onChanged: (value) {},
            onDecrement: () {
              if (_qty <= 0) {
                return;
              }
              _qtyController.text = '${_qty - 1}';
            },
            onIncrement: () {
              _qtyController.text = '${_qty + 1}';
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('reconciliation-sale-modal-unit-price-field'),
            controller: _priceController,
            focusNode: _priceFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: VN.donGiaNhapTay,
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: InputDecoration(
              labelText: VN.phuongThucThanhToan,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _paymentMethodError ? VN.chonPhuongThucThanhToan : null,
            ),
            items: kReconciliationPaymentMethodItems,
            onChanged: (value) => setState(() {
              _paymentMethod = value;
              _paymentMethodError = false;
            }),
          ),
        ],
      ),
    );
  }
}

class _ReconciliationWasteModalContent extends ConsumerStatefulWidget {
  const _ReconciliationWasteModalContent({
    required this.product,
    required this.option,
    required this.optionKey,
    required this.initialCounted,
    required this.initialSaleRows,
    required this.initialWaste,
    required this.initialWasteReason,
    required this.notifier,
  });

  final ReconciliationDraftProduct product;
  final ReconciliationDraftOption option;
  final String optionKey;
  final int initialCounted;
  final List<ReconciliationSaleRowInput> initialSaleRows;
  final int initialWaste;
  final String initialWasteReason;
  final ReconciliationNotifier notifier;

  @override
  ConsumerState<_ReconciliationWasteModalContent> createState() =>
      _ReconciliationWasteModalContentState();
}

class _ReconciliationWasteModalContentState
    extends ConsumerState<_ReconciliationWasteModalContent> {
  late final TextEditingController _wasteController;
  late final TextEditingController _wasteReasonController;
  bool _wasteReasonError = false;

  @override
  void initState() {
    super.initState();
    _wasteController = TextEditingController(text: '${widget.initialWaste}');
    _wasteReasonController = TextEditingController(
      text: widget.initialWasteReason,
    );
    _wasteController.addListener(_onWasteQtyChanged);
  }

  void _onWasteQtyChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _wasteController.removeListener(_onWasteQtyChanged);
    _wasteController.dispose();
    _wasteReasonController.dispose();
    super.dispose();
  }

  int get _qty => int.tryParse(_wasteController.text) ?? 0;

  void _submit() {
    if (_qty > 0 && _wasteReasonController.text.trim().isEmpty) {
      setState(() => _wasteReasonError = true);
      return;
    }
    widget.notifier.setWasteQty(widget.optionKey, _qty);
    widget.notifier.setWasteReasonForOption(
      widget.optionKey,
      _wasteReasonController.text,
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    final counted =
        state.countedQtyByOption[widget.optionKey] ?? widget.initialCounted;
    final saleRows =
        state.saleRowsByOption[widget.optionKey] ?? widget.initialSaleRows;
    final waste =
        state.wasteQtyByOption[widget.optionKey] ?? widget.initialWaste;
    final wasteReason =
        state.wasteReasonByOption[widget.optionKey] ?? widget.initialWasteReason;
    final saleQty = saleRows.fold<int>(0, (sum, row) => sum + row.quantity);
    final missing = widget.option.expectedQty - counted;
    final variance = widget.option.expectedQty - counted - saleQty - waste;

    final localQty = _qty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildReconciliationModalHandle(context),
              const SizedBox(height: 12),
              _buildTitle(context),
              const SizedBox(height: 12),
              _buildSummaryChips(
                context,
                expectedQty: widget.option.expectedQty,
                counted: counted,
                missing: missing,
                saleQty: saleQty,
                wasteQty: waste,
                variance: variance,
              ),
              const SizedBox(height: 12),
              buildReconciliationProductHeader(
                context,
                product: widget.product,
                option: widget.option,
              ),
              const SizedBox(height: 16),
              _buildExistingWaste(context, waste, wasteReason),
              const SizedBox(height: 16),
              _buildWasteForm(context, localQty),
              const SizedBox(height: 16),
              buildReconciliationModalActions(context, onSubmit: _submit),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      VN.haoHutSheet,
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildExistingWaste(BuildContext context, int waste, String wasteReason) {
    if (waste <= 0 && wasteReason.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${VN.soLuongHaoHut}: $waste',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (wasteReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${VN.lyDoHaoHut}: $wasteReason',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWasteForm(BuildContext context, int qty) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReconciliationQuantityStepperField(
            label: VN.soLuongHaoHut,
            controller: _wasteController,
            onChanged: (value) {},
            onDecrement: () {
              if (_qty <= 0) {
                return;
              }
              _wasteController.text = '${_qty - 1}';
            },
            onIncrement: () {
              _wasteController.text = '${_qty + 1}';
            },
          ),
          if (qty > 0) ...[
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                labelText: VN.lyDoHaoHut,
                border: const OutlineInputBorder(),
                errorText: _wasteReasonError ? VN.lyDoRequired : null,
              ),
              controller: _wasteReasonController,
              onChanged: (_) {
                if (_wasteReasonError) {
                  setState(() => _wasteReasonError = false);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

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
