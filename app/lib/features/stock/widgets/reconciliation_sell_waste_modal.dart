import 'package:bakery_app/shared/utils.dart'
    show formatVND, paymentMethodLabel;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/reconciliation_models.dart';
import '../../../providers/reconciliation_provider.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import '../providers/reconciliation_sell_waste_modal_notifier.dart';
import 'reconciliation_shared_widgets.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/stock.dart';

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
  final draftContext = reconciliationActionDraftContext(
    productId: product.productId,
    optionKey: optionKey,
    action: 'sale',
    variantId: editingRowIndex == null ? 'add' : 'edit:$editingRowIndex',
  );
  final providerContainer = ProviderScope.containerOf(context);
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
      initialUnitPrice:
          editingRow?.unitPrice ?? option.normalizedPrice.toDouble(),
      initialPaymentMethod: editingRow?.paymentMethod,
    ),
  ).whenComplete(
    () => providerContainer
        .read(reconciliationSellWasteModalProvider(draftContext).notifier)
        .settleTransient(),
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
  final draftContext = reconciliationActionDraftContext(
    productId: product.productId,
    optionKey: optionKey,
    action: 'waste',
  );
  final providerContainer = ProviderScope.containerOf(context);
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
  ).whenComplete(
    () => providerContainer
        .read(reconciliationSellWasteModalProvider(draftContext).notifier)
        .settleTransient(),
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

  bool get _isEdit => widget.editingRowIndex != null;

  FormDraftContext get _draftContext => reconciliationActionDraftContext(
    productId: widget.product.productId,
    optionKey: widget.optionKey,
    action: 'sale',
    variantId: _isEdit ? 'edit:${widget.editingRowIndex}' : 'add',
  );

  @override
  void initState() {
    super.initState();
    final draft = ref.read(reconciliationSellWasteModalProvider(_draftContext));
    _qtyController = TextEditingController(
      text: draft.initialized ? draft.quantity : '${widget.initialQty}',
    );
    _priceController = TextEditingController(
      text: draft.initialized
          ? draft.unitPrice
          : reconciliationPriceToText(widget.initialUnitPrice),
    );
    _qtyController.addListener(_persistQuantity);
    _priceController.addListener(_persistUnitPrice);
    final seedMethod = widget.initialPaymentMethod ?? kPaymentMethodCash;
    // Deferred to a microtask so we don't mutate providers during the
    // widget-tree build phase (DG-404 Phase 4.7).
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
          .initializeSale(
            quantity: _qtyController.text,
            unitPrice: _priceController.text,
            method: seedMethod,
          );
    });
  }

  void _persistQuantity() => ref
      .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
      .setQuantity(_qtyController.text);

  void _persistUnitPrice() => ref
      .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
      .setUnitPrice(_priceController.text);

  @override
  void dispose() {
    _qtyController.removeListener(_persistQuantity);
    _priceController.removeListener(_persistUnitPrice);
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
    final modalState = ref.read(
      reconciliationSellWasteModalProvider(_draftContext),
    );
    final paymentMethod = modalState.paymentMethod;
    if (editingIndex == null) {
      if (_qty <= 0) {
        ref
            .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
            .clear();
        Navigator.of(context).pop(true);
        return;
      }
      if (_qty > 0 && paymentMethod == null) {
        ref
            .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
            .setPaymentMethodError(true);
        return;
      }
      widget.notifier.addSaleRow(
        widget.optionKey,
        defaultUnitPrice: widget.option.normalizedPrice,
      );
      final rowIndex =
          (ref
                      .read(reconciliationProvider)
                      .saleRowsByOption[widget.optionKey] ??
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
          paymentMethod,
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
        paymentMethod,
      );
    }
    ref
        .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
        .clear();
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
              Consumer(
                builder: (context, ref, _) {
                  final draft = ref.watch(
                    reconciliationSellWasteModalProvider(_draftContext),
                  );
                  return DiscardFormDraftAction(
                    isDirty:
                        draft.initialized &&
                        (draft.quantity != draft.initialQuantity ||
                            draft.unitPrice != draft.initialUnitPrice ||
                            draft.paymentMethod != draft.initialPaymentMethod),
                    onDiscard: () {
                      _qtyController.text = '${widget.initialQty}';
                      _priceController.text = reconciliationPriceToText(
                        widget.initialUnitPrice,
                      );
                      ref
                          .read(
                            reconciliationSellWasteModalProvider(
                              _draftContext,
                            ).notifier,
                          )
                          .discardSale(
                            quantity: '${widget.initialQty}',
                            unitPrice: reconciliationPriceToText(
                              widget.initialUnitPrice,
                            ),
                            paymentMethod:
                                widget.initialPaymentMethod ??
                                kPaymentMethodCash,
                          );
                    },
                  );
                },
              ),
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
      widget.editingRowIndex == null
          ? OrdersLabels.banHang
          : '${OrdersLabels.banHang} - ${StockLabels.sua}',
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
                    '${StockLabels.dongBan} ${rowIndex + 1}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${StockLabels.soLuongBan}: ${saleRows[rowIndex].quantity}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '${StockLabels.donGiaNhapTay}: ${formatVND(saleRows[rowIndex].unitPrice?.toDouble() ?? 0)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '${StockLabels.phuongThucThanhToan}: ${saleRows[rowIndex].paymentMethod == null ? "" : paymentMethodLabel(saleRows[rowIndex].paymentMethod!)}',
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
            onQtyChanged: (value) => widget.notifier.setSaleRowQty(
              widget.optionKey,
              rowIndex,
              value,
            ),
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
    final modalState = ref.watch(
      reconciliationSellWasteModalProvider(_draftContext),
    );
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
            label: StockLabels.soLuongBan,
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
              labelText: StockLabels.donGiaNhapTay,
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'reconciliation-payment-${widget.optionKey}-${modalState.paymentMethod}',
            ),
            initialValue: modalState.paymentMethod,
            decoration: InputDecoration(
              labelText: StockLabels.phuongThucThanhToan,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: modalState.paymentMethodError
                  ? StockLabels.chonPhuongThucThanhToan
                  : null,
            ),
            items: kReconciliationPaymentMethodItems,
            onChanged: (value) => ref
                .read(
                  reconciliationSellWasteModalProvider(_draftContext).notifier,
                )
                .setPaymentMethod(value),
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

  FormDraftContext get _draftContext => reconciliationActionDraftContext(
    productId: widget.product.productId,
    optionKey: widget.optionKey,
    action: 'waste',
  );

  @override
  void initState() {
    super.initState();
    final draft = ref.read(reconciliationSellWasteModalProvider(_draftContext));
    _wasteController = TextEditingController(
      text: draft.initialized ? draft.quantity : '${widget.initialWaste}',
    );
    _wasteReasonController = TextEditingController(
      text: draft.initialized ? draft.wasteReason : widget.initialWasteReason,
    );
    _wasteController.addListener(_onWasteQtyChanged);
    _wasteController.addListener(_persistQuantity);
    _wasteReasonController.addListener(_persistWasteReason);
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
          .initializeWaste(
            quantity: _wasteController.text,
            reason: _wasteReasonController.text,
          );
    });
  }

  void _persistQuantity() => ref
      .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
      .setQuantity(_wasteController.text);

  void _persistWasteReason() => ref
      .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
      .setWasteReason(_wasteReasonController.text);

  void _onWasteQtyChanged() {
    if (mounted) {
      ref
          .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
          .rebuild();
    }
  }

  @override
  void dispose() {
    _wasteController.removeListener(_onWasteQtyChanged);
    _wasteController.removeListener(_persistQuantity);
    _wasteReasonController.removeListener(_persistWasteReason);
    _wasteController.dispose();
    _wasteReasonController.dispose();
    super.dispose();
  }

  int get _qty => int.tryParse(_wasteController.text) ?? 0;

  void _submit() {
    if (_qty > 0 && _wasteReasonController.text.trim().isEmpty) {
      ref
          .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
          .setWasteReasonError(true);
      return;
    }
    widget.notifier.setWasteQty(widget.optionKey, _qty);
    widget.notifier.setWasteReasonForOption(
      widget.optionKey,
      _wasteReasonController.text,
    );
    ref
        .read(reconciliationSellWasteModalProvider(_draftContext).notifier)
        .clear();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    // Watch the modal form state so rebuilds triggered by the
    // waste-qty controller listener (via `rebuild()`) refresh the
    // conditional reason field, and so `wasteReasonError` updates.
    final modalDraft = ref.watch(
      reconciliationSellWasteModalProvider(_draftContext),
    );
    final counted =
        state.countedQtyByOption[widget.optionKey] ?? widget.initialCounted;
    final saleRows =
        state.saleRowsByOption[widget.optionKey] ?? widget.initialSaleRows;
    final waste =
        state.wasteQtyByOption[widget.optionKey] ?? widget.initialWaste;
    final wasteReason =
        state.wasteReasonByOption[widget.optionKey] ??
        widget.initialWasteReason;
    final saleQty = saleRows.fold<int>(0, (sum, row) => sum + row.quantity);
    final missing = widget.option.expectedQty - counted;
    final variance = widget.option.expectedQty - counted - saleQty - waste;

    final localQty = _qty;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
              DiscardFormDraftAction(
                isDirty:
                    modalDraft.initialized &&
                    (modalDraft.quantity != modalDraft.initialQuantity ||
                        modalDraft.wasteReason !=
                            modalDraft.initialWasteReason),
                onDiscard: () {
                  _wasteController.text = '${widget.initialWaste}';
                  _wasteReasonController.text = widget.initialWasteReason;
                  ref
                      .read(
                        reconciliationSellWasteModalProvider(
                          _draftContext,
                        ).notifier,
                      )
                      .discardWaste(
                        quantity: '${widget.initialWaste}',
                        reason: widget.initialWasteReason,
                      );
                },
              ),
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
      StockLabels.haoHutSheet,
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildExistingWaste(
    BuildContext context,
    int waste,
    String wasteReason,
  ) {
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
            '${StockLabels.soLuongHaoHut}: $waste',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (wasteReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${StockLabels.lyDoHaoHut}: $wasteReason',
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
            label: StockLabels.soLuongHaoHut,
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
                labelText: StockLabels.lyDoHaoHut,
                border: const OutlineInputBorder(),
                errorText:
                    ref
                        .watch(
                          reconciliationSellWasteModalProvider(_draftContext),
                        )
                        .wasteReasonError
                    ? StockLabels.lyDoRequired
                    : null,
              ),
              controller: _wasteReasonController,
              onChanged: (_) {
                if (ref
                    .read(reconciliationSellWasteModalProvider(_draftContext))
                    .wasteReasonError) {
                  ref
                      .read(
                        reconciliationSellWasteModalProvider(
                          _draftContext,
                        ).notifier,
                      )
                      .clearWasteReasonError();
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
      ReconciliationSummaryChip(
        label: StockLabels.tonDuKien,
        value: expectedQty,
      ),
      ReconciliationSummaryChip(label: StockLabels.tonDaDem, value: counted),
      ReconciliationSummaryChip(
        label: StockLabels.soLuongThieu,
        value: missing < 0 ? 0 : missing,
      ),
      ReconciliationSummaryChip(label: StockLabels.soLuongBan, value: saleQty),
      ReconciliationSummaryChip(
        label: StockLabels.soLuongHaoHut,
        value: wasteQty,
      ),
      ReconciliationVarianceChip(variance: variance),
    ],
  );
}
