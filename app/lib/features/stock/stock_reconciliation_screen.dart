import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/reconciliation_service.dart';
import '../../data/providers/reconciliation_provider.dart';
import '../../providers/events_provider.dart';
import '../../providers/products_provider.dart';
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
                  final ok = await _confirmBeforeSubmit(
                    context,
                    state,
                    staffName,
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
                  final isWasteOverInventory = nextState.errorMessage != null &&
                      nextState.errorMessage!.contains('Số hao hụt vượt quá số thiếu');
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
                            : success && nextState.lastSubmittedSessionId != null
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
          child: draft.products.isEmpty
              ? const Center(child: Text(VN.khongCoSanPhamTrungBay))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: draft.products.length,
                  itemBuilder: (context, index) {
                    final product = draft.products[index];
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
  ) async {
    final draft = state.draft;
    if (draft == null) {
      return false;
    }

    var totalSale = 0;
    var totalWaste = 0;
    for (final product in draft.products) {
      final rows = state.saleRowsByProduct[product.productId] ??
          const <ReconciliationSaleRowInput>[];
      totalSale += rows.fold<int>(0, (sum, row) => sum + row.quantity);
      totalWaste += state.wasteQtyByProduct[product.productId] ?? 0;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final hasEmptyWasteReason = draft.products.any((product) {
          final waste = state.wasteQtyByProduct[product.productId] ?? 0;
          if (waste > 0) {
            final reason = (state.wasteReasonByProduct[product.productId] ?? '').trim();
            return reason.isEmpty;
          }
          return false;
        });

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
              if (state.hasWaste && hasEmptyWasteReason)
                Text(
                  '(${VN.lyDoHaoHut}: ${VN.khongCo})',
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
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(VN.guiDoiSoat),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }
}

class _ProductCard extends ConsumerStatefulWidget {
  const _ProductCard({required this.product});

  final ReconciliationDraftProduct product;

  @override
  ConsumerState<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<_ProductCard> {
  late TextEditingController _countedController;
  late TextEditingController _wasteController;
  late TextEditingController _wasteReasonController;

  @override
  void initState() {
    super.initState();
    final productId = widget.product.productId;
    final state = ref.read(reconciliationProvider);
    final counted = state.countedQtyByProduct[productId] ?? widget.product.expectedQty;
    final waste = state.wasteQtyByProduct[productId] ?? 0;
    final wasteReason = state.wasteReasonByProduct[productId] ?? '';

    _countedController = TextEditingController(text: '$counted');
    _wasteController = TextEditingController(text: '$waste');
    _wasteReasonController = TextEditingController(text: wasteReason);
  }

  @override
  void dispose() {
    _countedController.dispose();
    _wasteController.dispose();
    _wasteReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reconciliationProvider);
    final notifier = ref.read(reconciliationProvider.notifier);
    final counted =
        state.countedQtyByProduct[widget.product.productId] ?? widget.product.expectedQty;
    final saleRows = state.saleRowsByProduct[widget.product.productId] ??
        const <ReconciliationSaleRowInput>[];
    final waste = state.wasteQtyByProduct[widget.product.productId] ?? 0;
    final missing = widget.product.expectedQty - counted;
    final productError = state.productErrors[widget.product.productId];
    final saleRowErrors =
        state.saleRowErrorsByProduct[widget.product.productId] ??
        const <ReconciliationSaleRowError>[];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.product.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${VN.tonDuKien}: ${widget.product.expectedQty}'),
            Text('${VN.giaCoSo}: ${widget.product.basePrice.toStringAsFixed(0)}đ'),
            const SizedBox(height: 12),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: VN.tonDaDem,
                border: OutlineInputBorder(),
              ),
              controller: _countedController,
              onChanged: (value) {
                final parsed = int.tryParse(value) ?? 0;
                notifier.setCountedQty(widget.product.productId, parsed);
              },
            ),
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
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: VN.soLuongHaoHut,
                  border: OutlineInputBorder(),
                ),
                controller: _wasteController,
                onChanged: (value) {
                  notifier.setWasteQty(
                    widget.product.productId,
                    int.tryParse(value) ?? 0,
                  );
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => notifier.addSaleRow(widget.product.productId),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm dòng bán'),
                ),
              ),
              for (var rowIndex = 0; rowIndex < saleRows.length; rowIndex++)
                _SaleRowEditor(
                  rowIndex: rowIndex,
                  row: saleRows[rowIndex],
                  product: widget.product,
                  rowError: rowIndex < saleRowErrors.length
                      ? saleRowErrors[rowIndex]
                      : null,
                  onQtyChanged: (value) => notifier.setSaleRowQty(
                    widget.product.productId,
                    rowIndex,
                    int.tryParse(value) ?? 0,
                  ),
                  onPriceChanged: (value) => notifier.setSaleRowUnitPrice(
                    widget.product.productId,
                    rowIndex,
                    value,
                  ),
                  onMethodChanged: (value) => notifier.setSaleRowPaymentMethod(
                    widget.product.productId,
                    rowIndex,
                    value,
                  ),
                  onRemove: () => notifier.removeSaleRow(
                    widget.product.productId,
                    rowIndex,
                  ),
                  onPriceChipTap: (price) => notifier.fillSaleRowPriceFromChip(
                    widget.product.productId,
                    rowIndex,
                    price,
                  ),
                ),
            ],
            if (waste > 0) ...[
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: VN.lyDoHaoHut,
                  border: OutlineInputBorder(),
                ),
                controller: _wasteReasonController,
                onChanged: (value) {
                  notifier.setWasteReasonForProduct(widget.product.productId, value);
                },
              ),
            ],
            if (productError != null) ...[
              const SizedBox(height: 8),
              Text(
                productError,
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SaleRowEditor extends StatelessWidget {
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
  final ValueChanged<String> onQtyChanged;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<String?> onMethodChanged;
  final VoidCallback onRemove;
  final ValueChanged<double> onPriceChipTap;

  @override
  Widget build(BuildContext context) {
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
              Text('Dòng bán ${rowIndex + 1}'),
              const Spacer(),
              IconButton(
                tooltip: VN.xoa,
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextFormField(
            key: ValueKey(
              'sale-row-qty-$rowIndex-${product.productId}-${row.quantity}',
            ),
            keyboardType: TextInputType.number,
            initialValue: '${row.quantity}',
            onChanged: onQtyChanged,
            decoration: InputDecoration(
              labelText: VN.soLuongBan,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: rowError?.quantity,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey(
              'sale-row-price-$rowIndex-${product.productId}-${row.unitPrice}',
            ),
            keyboardType: TextInputType.number,
            initialValue: row.unitPrice,
            onChanged: onPriceChanged,
            decoration: InputDecoration(
              labelText: VN.donGiaNhapTay,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: rowError?.unitPrice,
            ),
          ),
          if (product.priceChips.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: product.priceChips
                  .map(
                    (chip) => ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${chip.label}: ${chip.price.toStringAsFixed(0)}đ'),
                      onPressed: () => onPriceChipTap(chip.price),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: row.paymentMethod,
            decoration: InputDecoration(
              labelText: VN.phuongThucThanhToan,
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: rowError?.paymentMethod,
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text(VN.methodCash)),
              DropdownMenuItem(value: 'transfer', child: Text(VN.methodTransfer)),
            ],
            onChanged: onMethodChanged,
          ),
        ],
      ),
    );
  }
}
