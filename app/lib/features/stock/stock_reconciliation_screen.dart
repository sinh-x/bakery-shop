import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/reconciliation_service.dart';
import '../../data/providers/reconciliation_provider.dart';
import '../../data/models/category.dart';
import '../../providers/categories_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/utils/category_grouping.dart';
import '../../shared/widgets/collapsible_category_sections.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'stock_screen.dart';

class StockReconciliationScreen extends ConsumerStatefulWidget {
  const StockReconciliationScreen({super.key});

  @override
  ConsumerState<StockReconciliationScreen> createState() =>
      _StockReconciliationScreenState();
}

class _StockReconciliationScreenState
    extends ConsumerState<StockReconciliationScreen> {
  final CategorySectionExpansionController _categoryExpansionController =
      CategorySectionExpansionController();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(reconciliationProvider.notifier).loadDraft(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    final notifier = ref.read(reconciliationProvider.notifier);
    final staffName = ref.watch(loggedByProvider).trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.doiSoatTonKhoHomNay),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: state.isSubmitting ? null : notifier.loadDraft,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: VN.lichSuDoiSoatTonKho,
            onPressed: state.isSubmitting
                ? null
                : () => context.push('/stock/reconciliation/history'),
          ),
        ],
      ),
      body: state.isLoading && state.draft == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, state, staffName),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: state.isSubmitting
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final canSubmit = ref
                      .read(reconciliationProvider.notifier)
                      .prepareSubmitReview();
                  final previewState = ref.read(reconciliationProvider);
                  final ok = await _confirmBeforeSubmit(
                    context,
                    previewState,
                    staffName,
                    canSubmit,
                  );
                  if (!ok) {
                    return;
                  }
                  if (!mounted) {
                    return;
                  }
                  final success = await ref
                      .read(reconciliationProvider.notifier)
                      .submit();
                  if (!mounted) {
                    return;
                  }
                  final nextState = ref.read(reconciliationProvider);
                  if (success) {
                    ref.invalidate(productsProvider);
                    ref.invalidate(stockOverviewProvider);
                    ref.invalidate(reconciliationHistoryListProvider);
                  }
                  final message = success
                      ? (nextState.submitSuccessMessage ?? VN.doiSoatThanhCong)
                      : (nextState.errorMessage ?? VN.doiSoatThatBai);
                  final background = success
                      ? Colors.green[700]
                      : Colors.red[700];
                  final isWasteOverInventory =
                      nextState.errorMessage != null &&
                      nextState.errorMessage!.contains(
                        'Số hao hụt vượt quá số thiếu',
                      );
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: background,
                        action: isWasteOverInventory
                            ? SnackBarAction(
                                label: VN.nhapHangSheet,
                                onPressed: () => context.push('/stock'),
                              )
                            : success &&
                                  nextState.lastSubmittedSessionId != null
                            ? SnackBarAction(
                                label: VN.xemLichSu,
                                onPressed: () => context.push(
                                  '/stock/reconciliation/history/${nextState.lastSubmittedSessionId}',
                                ),
                              )
                            : null,
                      ),
                    );
                },
          icon: state.isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(state.isSubmitting ? VN.dangGuiDoiSoat : VN.guiDoiSoat),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ReconciliationState state,
    String staffName,
  ) {
    final categories =
        ref.watch(categoriesProvider).asData?.value ?? const <Category>[];
    final draft = state.draft;
    if (draft == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              state.errorMessage ?? VN.khongTheTaiDuLieuDoiSoat,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(VN.huongDanTaiLaiDoiSoat, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(reconciliationProvider.notifier).loadDraft(),
              icon: const Icon(Icons.refresh),
              label: const Text(VN.taiLai),
            ),
          ],
        ),
      );
    }

    final filteredProducts = draft.products
        .where((product) => product.expectedQty > 0)
        .toList(growable: false);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.orange.withValues(alpha: 0.08),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${VN.ngayDoiSoat}: ${draft.date}'),
              const SizedBox(height: 4),
              Text(
                '${VN.nhanVien}: ${staffName.isEmpty ? VN.chuaChonNhanVien : staffName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorMessage!,
                  style: TextStyle(
                    color: Colors.red[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: filteredProducts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 48),
                        const SizedBox(height: 12),
                        const Text(VN.khongCoSanPhamTrungBay),
                        const SizedBox(height: 8),
                        const Text(
                          VN.huongDanKhongCoSanPhamTrungBay,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => ref
                              .read(reconciliationProvider.notifier)
                              .loadDraft(),
                          icon: const Icon(Icons.refresh),
                          label: const Text(VN.taiLai),
                        ),
                      ],
                    ),
                  ),
                )
              : CollapsibleCategorySections<ReconciliationDraftProduct>(
                  sections: groupItemsByCategory<ReconciliationDraftProduct>(
                    items: filteredProducts,
                    categories: categories,
                    categoryKeyOf: (product) => product.category,
                    itemLabelOf: (product) => product.name,
                  ),
                  expansionController: _categoryExpansionController,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                  itemBuilder: (context, product) {
                    return _ProductCard(product: product);
                  },
                ),
        ),
      ],
    );
  }

  Future<bool> _confirmBeforeSubmit(
    BuildContext context,
    ReconciliationState state,
    String staffName,
    bool canSubmit,
  ) async {
    final draft = state.draft;
    if (draft == null) {
      return false;
    }

    var totalSale = 0;
    var totalWaste = 0;
    for (final product in draft.products) {
      for (final option in product.options) {
        final optionKey = reconciliationOptionKey(
          product.productId,
          option.normalizedPrice,
        );
        final rows =
            state.saleRowsByOption[optionKey] ??
            const <ReconciliationSaleRowInput>[];
        totalSale += rows.fold<int>(0, (sum, row) => sum + row.quantity);
        totalWaste += state.wasteQtyByOption[optionKey] ?? 0;
      }
    }

    final issues = _collectUnresolvedIssues(state);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(VN.xacNhanGuiDoiSoat),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${VN.nhanVien}: ${staffName.isEmpty ? VN.chuaChonNhanVien : staffName}',
              ),
              const SizedBox(height: 4),
              Text('${VN.tongSoLuongBan}: $totalSale'),
              Text('${VN.tongSoLuongHaoHut}: $totalWaste'),
              const SizedBox(height: 8),
              Text(
                VN.vanDeCanXuLyTruocKhiGui,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (issues.isEmpty)
                Text(
                  VN.daSanSangGuiDoiSoat,
                  style: TextStyle(color: Colors.green[700]),
                )
              else
                ...issues.map(
                  (issue) => Text(
                    '- $issue',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!canSubmit)
                Text(
                  VN.daTatGuiDoiSoatKhiCoLoi,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(VN.huy),
            ),
            FilledButton(
              onPressed: canSubmit
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text(VN.guiDoiSoat),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  List<String> _collectUnresolvedIssues(ReconciliationState state) {
    final draft = state.draft;
    if (draft == null) {
      return <String>[];
    }

    final optionNameByKey = <String, String>{};
    for (final product in draft.products) {
      for (final option in product.options) {
        final key = reconciliationOptionKey(
          product.productId,
          option.normalizedPrice,
        );
        optionNameByKey[key] =
            '${product.name} - Gia ${option.normalizedPrice}';
      }
    }

    final issues = <String>[];
    for (final entry in state.optionErrors.entries) {
      final optionLabel = optionNameByKey[entry.key] ?? entry.key;
      issues.add('$optionLabel: ${entry.value}');
    }

    for (final entry in state.saleRowErrorsByOption.entries) {
      final optionLabel = optionNameByKey[entry.key] ?? entry.key;
      for (var index = 0; index < entry.value.length; index += 1) {
        final rowError = entry.value[index];
        final parts = <String>[
          if (rowError.quantity != null) rowError.quantity!,
          if (rowError.unitPrice != null) rowError.unitPrice!,
          if (rowError.paymentMethod != null) rowError.paymentMethod!,
        ];
        if (parts.isNotEmpty) {
          issues.add(
            '$optionLabel - ${VN.dongBan} ${index + 1}: ${parts.join(', ')}',
          );
        }
      }
    }
    return issues;
  }
}

class _ProductCard extends ConsumerStatefulWidget {
  const _ProductCard({required this.product});

  final ReconciliationDraftProduct product;

  @override
  ConsumerState<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<_ProductCard> {
  final Map<String, TextEditingController> _countedControllers = {};
  final Map<String, TextEditingController> _wasteControllers = {};
  final Map<String, TextEditingController> _wasteReasonControllers = {};
  bool _isExpanded = false;

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
      _wasteReasonControllers[optionKey] = TextEditingController(
        text: wasteReason,
      );
    }
  }

  bool _shouldShowSaleEditor(
    int missing,
    List<ReconciliationSaleRowInput> saleRows,
  ) {
    return missing > 0 || saleRows.isNotEmpty;
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
              for (final option in widget.product.options) ...[
                _OptionHeader(option: option),
                Builder(
                  builder: (context) {
                    final optionKey = reconciliationOptionKey(
                      widget.product.productId,
                      option.normalizedPrice,
                    );
                    final counted =
                        state.countedQtyByOption[optionKey] ??
                        option.expectedQty;
                    final saleRows =
                        state.saleRowsByOption[optionKey] ??
                        const <ReconciliationSaleRowInput>[];
                    final waste = state.wasteQtyByOption[optionKey] ?? 0;
                    final missing = option.expectedQty - counted;
                    final optionError = state.optionErrors[optionKey];
                    final saleRowErrors =
                        state.saleRowErrorsByOption[optionKey] ??
                        const <ReconciliationSaleRowError>[];
                    final showSaleEditor = _shouldShowSaleEditor(
                      missing,
                      saleRows,
                    );

                    final countedController = _countedControllers[optionKey]!;
                    final wasteController = _wasteControllers[optionKey]!;
                    final wasteReasonController =
                        _wasteReasonControllers[optionKey]!;
                    _syncIntController(countedController, counted);
                    _syncIntController(wasteController, waste);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QuantityStepperField(
                          label: VN.tonDaDem,
                          controller: countedController,
                          onChanged: (value) =>
                              notifier.setCountedQty(optionKey, value),
                          onDecrement: () {
                            if (counted <= 0) {
                              return;
                            }
                            notifier.setCountedQty(optionKey, counted - 1);
                          },
                          onIncrement: () =>
                              notifier.setCountedQty(optionKey, counted + 1),
                        ),
                        if (showSaleEditor) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => notifier.addSaleRow(
                                optionKey,
                                defaultUnitPrice: option.normalizedPrice,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text(VN.themDongBan),
                            ),
                          ),
                          for (
                            var rowIndex = 0;
                            rowIndex < saleRows.length;
                            rowIndex++
                          )
                            _SaleRowEditor(
                              rowIndex: rowIndex,
                              row: saleRows[rowIndex],
                              product: widget.product,
                              rowError: rowIndex < saleRowErrors.length
                                  ? saleRowErrors[rowIndex]
                                  : null,
                              onQtyChanged: (value) => notifier.setSaleRowQty(
                                optionKey,
                                rowIndex,
                                value,
                              ),
                              onPriceChanged: (value) =>
                                  notifier.setSaleRowUnitPrice(
                                    optionKey,
                                    rowIndex,
                                    value,
                                  ),
                              onMethodChanged: (value) =>
                                  notifier.setSaleRowPaymentMethod(
                                    optionKey,
                                    rowIndex,
                                    value,
                                  ),
                              onRemove: () =>
                                  notifier.removeSaleRow(optionKey, rowIndex),
                              onPriceChipTap: (price) =>
                                  notifier.fillSaleRowPriceFromChip(
                                    optionKey,
                                    rowIndex,
                                    price,
                                  ),
                            ),
                        ],
                        if (missing > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${VN.soLuongThieu}: $missing',
                            style: TextStyle(
                              color: Colors.orange[800],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _QuantityStepperField(
                            label: VN.soLuongHaoHut,
                            controller: wasteController,
                            onChanged: (value) =>
                                notifier.setWasteQty(optionKey, value),
                            onDecrement: () {
                              if (waste <= 0) {
                                return;
                              }
                              notifier.setWasteQty(optionKey, waste - 1);
                            },
                            onIncrement: () =>
                                notifier.setWasteQty(optionKey, waste + 1),
                          ),
                          if (waste > 0) ...[
                            const SizedBox(height: 8),
                            TextField(
                              decoration: const InputDecoration(
                                labelText: VN.lyDoHaoHut,
                                border: OutlineInputBorder(),
                              ),
                              controller: wasteReasonController,
                              onChanged: (value) {
                                notifier.setWasteReasonForOption(
                                  optionKey,
                                  value,
                                );
                              },
                            ),
                          ],
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
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
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
  const _OptionHeader({required this.option});

  final ReconciliationDraftOption option;

  @override
  Widget build(BuildContext context) {
    final labels = option.chipLabelMetadata;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gia ${option.normalizedPrice} - ${VN.tonDuKien}: ${option.expectedQty}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (labels.isNotEmpty)
            Text(
              '${VN.nhanChip}: $labels',
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
    required this.product,
    required this.onQtyChanged,
    required this.onPriceChanged,
    required this.onMethodChanged,
    required this.onRemove,
    required this.onPriceChipTap,
    this.rowError,
  });

  final int rowIndex;
  final ReconciliationSaleRowInput row;
  final ReconciliationDraftProduct product;
  final ReconciliationSaleRowError? rowError;
  final ValueChanged<int> onQtyChanged;
  final ValueChanged<double?> onPriceChanged;
  final ValueChanged<String?> onMethodChanged;
  final VoidCallback onRemove;
  final ValueChanged<double> onPriceChipTap;

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

  String _priceToText(double? price) {
    if (price == null) {
      return '';
    }
    return price == price.roundToDouble()
        ? price.toInt().toString()
        : price.toString();
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
          if (widget.product.priceChips.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.product.priceChips
                  .map(
                    (chip) => ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${chip.label}: ${chip.price.toStringAsFixed(0)}đ',
                      ),
                      onPressed: () => widget.onPriceChipTap(chip.price),
                    ),
                  )
                  .toList(),
            ),
          ],
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
