import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/reconciliation_service.dart';
import '../../data/providers/reconciliation_provider.dart';
import '../../providers/events_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

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
                  final message = success
                      ? (nextState.submitSuccessMessage ?? VN.doiSoatThanhCong)
                      : (nextState.errorMessage ?? VN.doiSoatThatBai);
                  final background = success
                      ? Colors.green[700]
                      : Colors.red[700];
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: background,
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
        _SubmitOptionsPanel(state: state),
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
      totalSale += state.saleQtyByProduct[product.productId] ?? 0;
      totalWaste += state.wasteQtyByProduct[product.productId] ?? 0;
    }

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
              if (state.hasSale)
                Text(
                  '${VN.phuongThucThanhToan}: ${paymentMethodLabel(state.paymentMethod ?? '')}',
                ),
              if (state.hasWaste)
                Text('${VN.lyDoHaoHut}: ${state.wasteReason.trim()}'),
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

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product});

  final ReconciliationDraftProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reconciliationProvider);
    final notifier = ref.read(reconciliationProvider.notifier);
    final counted =
        state.countedQtyByProduct[product.productId] ?? product.expectedQty;
    final sale = state.saleQtyByProduct[product.productId] ?? 0;
    final waste = state.wasteQtyByProduct[product.productId] ?? 0;
    final missing = product.expectedQty - counted;
    final manualPrice = state.manualUnitPriceByProduct[product.productId] ?? '';

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${VN.tonDuKien}: ${product.expectedQty}'),
            Text('${VN.giaCoSo}: ${product.basePrice.toStringAsFixed(0)}đ'),
            if (product.priceChips.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: product.priceChips
                    .map(
                      (chip) => Chip(
                        label: Text(
                          '${chip.label}: ${chip.price.toStringAsFixed(0)}đ',
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 12),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: VN.tonDaDem,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(
                text: '$counted',
              )..selection = TextSelection.collapsed(offset: '$counted'.length),
              onChanged: (value) {
                final parsed = int.tryParse(value) ?? 0;
                notifier.setCountedQty(product.productId, parsed);
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: VN.soLuongBan,
                        border: OutlineInputBorder(),
                      ),
                      controller: TextEditingController(text: '$sale')
                        ..selection = TextSelection.collapsed(
                          offset: '$sale'.length,
                        ),
                      onChanged: (value) {
                        notifier.setSaleQty(
                          product.productId,
                          int.tryParse(value) ?? 0,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: VN.soLuongHaoHut,
                        border: OutlineInputBorder(),
                      ),
                      controller: TextEditingController(text: '$waste')
                        ..selection = TextSelection.collapsed(
                          offset: '$waste'.length,
                        ),
                      onChanged: (value) {
                        notifier.setWasteQty(
                          product.productId,
                          int.tryParse(value) ?? 0,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
            if (sale > 0) ...[
              const SizedBox(height: 8),
              TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: VN.donGiaNhapTay,
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: manualPrice)
                  ..selection = TextSelection.collapsed(
                    offset: manualPrice.length,
                  ),
                onChanged: (value) {
                  notifier.setManualUnitPrice(product.productId, value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubmitOptionsPanel extends ConsumerWidget {
  const _SubmitOptionsPanel({required this.state});

  final ReconciliationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(reconciliationProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.hasSale)
            DropdownButtonFormField<String>(
              initialValue: state.paymentMethod,
              decoration: const InputDecoration(
                labelText: VN.phuongThucThanhToan,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text(VN.methodCash)),
                DropdownMenuItem(
                  value: 'transfer',
                  child: Text(VN.methodTransfer),
                ),
              ],
              onChanged: notifier.setPaymentMethod,
            ),
          if (state.hasSale) const SizedBox(height: 8),
          if (state.hasWaste)
            TextField(
              decoration: const InputDecoration(
                labelText: VN.lyDoHaoHut,
                border: OutlineInputBorder(),
              ),
              onChanged: notifier.setWasteReason,
            ),
        ],
      ),
    );
  }
}
