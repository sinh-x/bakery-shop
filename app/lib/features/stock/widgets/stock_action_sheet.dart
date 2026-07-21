import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/stock_service.dart';
import 'package:bakery_app/shared/labels/shared.dart';

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
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  int? _selectedNormalizedPrice;

  String get _title {
    switch (widget.actionType) {
      case ActionType.restock:
        return VN.nhapHangSheet;
      case ActionType.waste:
        return VN.haoHutSheet;
      case ActionType.adjust:
        return VN.dieuChinhSheet;
    }
  }

  String get _submitLabel {
    switch (widget.actionType) {
      case ActionType.restock:
        return VN.xacNhanNhapHang;
      case ActionType.waste:
        return VN.xacNhanHaoHut;
      case ActionType.adjust:
        return VN.xacNhanDieuChinh;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final perChip = widget.item.perChip;
    if (perChip.isNotEmpty) {
      final provided = widget.initialPrice;
      _selectedNormalizedPrice = (provided != null &&
              perChip.any((c) => c.normalizedPrice == provided))
          ? provided
          : perChip.first.normalizedPrice;
    } else {
      _selectedNormalizedPrice = null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final quantity = int.tryParse(_quantityController.text) ?? 0;
    if (quantity <= 0) {
      showTopSnackBar(context, VN.soLuongInvalid, backgroundColor: Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final service = ref.read(stockServiceProvider);
      switch (widget.actionType) {
        case ActionType.restock:
          await service.restock(
            widget.item.productId,
            quantity,
            note: _noteController.text,
            normalizedPrice: _selectedNormalizedPrice,
          );
        case ActionType.waste:
          await service.waste(
            widget.item.productId,
            quantity,
            _reasonController.text,
            normalizedPrice: _selectedNormalizedPrice,
          );
        case ActionType.adjust:
          await service.adjust(
            widget.item.productId,
            quantity,
            _reasonController.text,
            normalizedPrice: _selectedNormalizedPrice,
          );
      }
      widget.onDone();
    } catch (e) {
      debugPrint('Stock action failed: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        showTopSnackBar(context, VN.loiHeThong, backgroundColor: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                              '${VN.tonKho} hiện tại: ${widget.item.totalQuantity}',
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
                    initialValue: _selectedNormalizedPrice,
                    decoration: const InputDecoration(
                      labelText: VN.tuyChonGia,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.sell_outlined),
                    ),
                    items: widget.item.perChip
                        .map(
                          (option) {
                            final price = option.normalizedPrice;
                            final priceText =
                                '${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}đ';
                            return DropdownMenuItem<int>(
                              value: option.normalizedPrice,
                              child: Text('${option.displayLabel} - $priceText (${option.quantity})'),
                            );
                          },
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedNormalizedPrice = value);
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Quantity input with +/- buttons
                Row(
                  children: [
                    IconButton.filled(
                      onPressed: () {
                        final current = int.tryParse(_quantityController.text) ?? 0;
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
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: VN.soLuong,
                          hintText: widget.actionType == ActionType.adjust
                              ? 'Nhập số lượng mới'
                              : 'Nhập số lượng',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return VN.fieldRequired;
                          }
                          final qty = int.tryParse(value);
                          if (qty == null || qty <= 0) {
                            return VN.soLuongInvalid;
                          }
                          return null;
                        },
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () {
                        final current = int.tryParse(_quantityController.text) ?? 0;
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
                      labelText: VN.ghiChuLabel,
                      hintText: VN.ghiChuHint,
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
                      labelText: VN.lyDoLabel,
                      hintText: VN.lyDoHint,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                    maxLines: 2,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return VN.lyDoRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                const SizedBox(height: 8),

                // Submit button
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
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
                  child: const Text(VN.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
