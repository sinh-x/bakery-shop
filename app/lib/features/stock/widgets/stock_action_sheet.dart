import 'package:bakery_app/shared/utils.dart'
    show categoryEmojiMap, showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/stock_service.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import '../providers/stock_action_sheet_notifier.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/labels/stock.dart';

enum ActionType { restock, waste, adjust }

/// Stock action bottom sheet for restock, waste, and adjust operations.
class StockActionSheet extends ConsumerStatefulWidget {
  const StockActionSheet({
    super.key,
    required this.item,
    required this.actionType,
    required this.onDone,
    this.initialPrice,
  });

  final StockOverviewItem item;
  final ActionType actionType;
  final VoidCallback onDone;

  /// Optional pre-selected normalized price (e.g. from a chip tap).
  /// When non-null and present in [StockOverviewItem.perChip], the dropdown
  /// starts on this price. When null, falls back to the first perChip price
  /// (existing behavior).
  final int? initialPrice;

  @override
  ConsumerState<StockActionSheet> createState() => _StockActionSheetState();
}

class _StockActionSheetState extends ConsumerState<StockActionSheet> {
  late final TextEditingController _quantityController;
  late final TextEditingController _reasonController;
  late final TextEditingController _noteController;
  final _formKey = GlobalKey<FormState>();

  int? get _initialNormalizedPrice {
    final perChip = widget.item.perChip;
    if (perChip.isEmpty) return null;
    final provided = widget.initialPrice;
    return provided != null &&
            perChip.any((option) => option.normalizedPrice == provided)
        ? provided
        : perChip.first.normalizedPrice;
  }

  FormDraftContext get _draftContext => stockActionDraftContext(
    productId: widget.item.productId,
    action: widget.actionType.name,
    normalizedPrice: _initialNormalizedPrice,
  );

  String get _title {
    switch (widget.actionType) {
      case ActionType.restock:
        return StockLabels.nhapHangSheet;
      case ActionType.waste:
        return StockLabels.haoHutSheet;
      case ActionType.adjust:
        return StockLabels.dieuChinhSheet;
    }
  }

  String get _submitLabel {
    switch (widget.actionType) {
      case ActionType.restock:
        return StockLabels.xacNhanNhapHang;
      case ActionType.waste:
        return StockLabels.xacNhanHaoHut;
      case ActionType.adjust:
        return StockLabels.xacNhanDieuChinh;
    }
  }

  @override
  void dispose() {
    _quantityController.removeListener(_persistQuantity);
    _reasonController.removeListener(_persistReason);
    _noteController.removeListener(_persistNote);
    _quantityController.dispose();
    _reasonController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final draft = ref.read(stockActionSheetProvider(_draftContext));
    _quantityController = TextEditingController(text: draft.quantity)
      ..addListener(_persistQuantity);
    _reasonController = TextEditingController(text: draft.reason)
      ..addListener(_persistReason);
    _noteController = TextEditingController(text: draft.note)
      ..addListener(_persistNote);
    final selected = _initialNormalizedPrice;
    // Deferred to a microtask so we don't mutate providers during the
    // widget-tree build phase (DG-404 Phase 4.7).
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(stockActionSheetProvider(_draftContext).notifier)
          .initialize(selected);
    });
  }

  void _persistQuantity() => ref
      .read(stockActionSheetProvider(_draftContext).notifier)
      .setQuantity(_quantityController.text);

  void _persistReason() => ref
      .read(stockActionSheetProvider(_draftContext).notifier)
      .setReason(_reasonController.text);

  void _persistNote() => ref
      .read(stockActionSheetProvider(_draftContext).notifier)
      .setNote(_noteController.text);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final quantity = int.tryParse(_quantityController.text) ?? 0;
    if (quantity <= 0) {
      showTopSnackBar(
        context,
        StockLabels.soLuongInvalid,
        backgroundColor: Colors.red,
      );
      return;
    }

    final draftNotifier = ref.read(
      stockActionSheetProvider(_draftContext).notifier,
    );
    final submittedDraft = draftNotifier.retainedDraft;
    draftNotifier.setLoading(true);
    final selectedNormalizedPrice = ref
        .read(stockActionSheetProvider(_draftContext))
        .selectedNormalizedPrice;

    try {
      final service = ref.read(stockServiceProvider);
      switch (widget.actionType) {
        case ActionType.restock:
          await service.restock(
            widget.item.productId,
            quantity,
            note: _noteController.text,
            normalizedPrice: selectedNormalizedPrice,
          );
        case ActionType.waste:
          await service.waste(
            widget.item.productId,
            quantity,
            _reasonController.text,
            normalizedPrice: selectedNormalizedPrice,
          );
        case ActionType.adjust:
          await service.adjust(
            widget.item.productId,
            quantity,
            _reasonController.text,
            normalizedPrice: selectedNormalizedPrice,
          );
      }
      draftNotifier.completeSuccess(submittedDraft);
      if (mounted) widget.onDone();
    } catch (e) {
      debugPrint('Stock action failed: $e');
      draftNotifier.setLoading(false);
      if (mounted) {
        showTopSnackBar(
          context,
          StockLabels.loiHeThong,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetState = ref.watch(stockActionSheetProvider(_draftContext));
    final isLoading = sheetState.isLoading;
    final selectedNormalizedPrice = sheetState.selectedNormalizedPrice;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Text(
                  _title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Product name
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        categoryEmojiMap[widget.item.category] ?? '🍰',
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.productName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${StockLabels.tonKho} hiện tại: ${widget.item.totalQuantity}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (widget.item.perChip.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    key: ValueKey(
                      'stock-price-${widget.item.productId}-$selectedNormalizedPrice',
                    ),
                    initialValue: selectedNormalizedPrice,
                    decoration: const InputDecoration(
                      labelText: StockLabels.tuyChonGia,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.sell_outlined),
                    ),
                    items: widget.item.perChip.map((option) {
                      final price = option.normalizedPrice;
                      final priceText =
                          '${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}đ';
                      return DropdownMenuItem<int>(
                        value: option.normalizedPrice,
                        child: Text(
                          '${option.displayLabel} - $priceText (${option.quantity})',
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      ref
                          .read(
                            stockActionSheetProvider(_draftContext).notifier,
                          )
                          .setSelectedNormalizedPrice(value);
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Quantity input with +/- buttons
                Row(
                  children: [
                    IconButton.filled(
                      onPressed: () {
                        final current =
                            int.tryParse(_quantityController.text) ?? 0;
                        if (current > 1) {
                          _quantityController.text = '${current - 1}';
                        }
                      },
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _quantityController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: OrdersLabels.soLuong,
                          hintText: widget.actionType == ActionType.adjust
                              ? 'Nhập số lượng mới'
                              : 'Nhập số lượng',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return SharedLabels.fieldRequired;
                          }
                          final qty = int.tryParse(value);
                          if (qty == null || qty <= 0) {
                            return StockLabels.soLuongInvalid;
                          }
                          return null;
                        },
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () {
                        final current =
                            int.tryParse(_quantityController.text) ?? 0;
                        _quantityController.text = '${current + 1}';
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Note (only for restock)
                if (widget.actionType == ActionType.restock) ...[
                  TextFormField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: StockLabels.ghiChuLabel,
                      hintText: StockLabels.ghiChuHint,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                ],

                // Reason (for waste and adjust)
                if (widget.actionType != ActionType.restock) ...[
                  TextFormField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      labelText: StockLabels.lyDoLabel,
                      hintText: StockLabels.lyDoHint,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                    maxLines: 2,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return StockLabels.lyDoRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                const SizedBox(height: 8),

                DiscardFormDraftAction(
                  isDirty:
                      sheetState.quantity.isNotEmpty ||
                      sheetState.reason.isNotEmpty ||
                      sheetState.note.isNotEmpty ||
                      sheetState.selectedNormalizedPrice !=
                          sheetState.initialNormalizedPrice,
                  onDiscard: () {
                    _quantityController.clear();
                    _reasonController.clear();
                    _noteController.clear();
                    ref
                        .read(stockActionSheetProvider(_draftContext).notifier)
                        .discard(_initialNormalizedPrice);
                  },
                ),

                // Submit button
                FilledButton(
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_submitLabel),
                ),
                const SizedBox(height: 8),

                // Cancel button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(SharedLabels.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
