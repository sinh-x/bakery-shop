import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blanks_provider.dart';
import '../../data/providers/bom_provider.dart';
import '../../shared/utils/format_double.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/blanks_states.dart';
import 'widgets/bom_add_sheet.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// BOM mapping screen for a single price_chip product (FR2/AC2).
///
/// Route: `/blanks/bom/:priceChipId`. The `:priceChipId` is the price_chip
/// id. Lists all blank→price_chip mappings with quantity, and supports
/// add / inline-edit quantity / remove with confirmation. Loading, empty,
/// and error states are rendered inline. Accessed from the product/price_chip
/// flow, not the blank detail screen (BOM is keyed by price_chip).
class BomMappingScreen extends ConsumerWidget {
  const BomMappingScreen({super.key, required this.priceChipId});

  final int priceChipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bomAsync = ref.watch(bomProvider(priceChipId));
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenBomMapping),
        actions: const [AppBarOverflowMenu()],
      ),
      body: bomAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => BlanksErrorView(
          onRetry: () => ref.invalidate(bomProvider(priceChipId)),
        ),
        data: (boms) {
          if (boms.isEmpty) {
            return const BlanksEmptyView(
              icon: Icons.inventory_2_outlined,
              label: BlanksLabels.emptyBom,
            );
          }
          return _BomListBody(priceChipId: priceChipId, boms: boms);
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: BlanksLabels.actionAddBom,
        onPressed: () => showBomAddSheet(context, priceChipId),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _BomListBody extends ConsumerWidget {
  const _BomListBody({required this.priceChipId, required this.boms});

  final int priceChipId;
  final List<ProductBlankBom> boms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Load the blank list so we can resolve blank names for display.
    final blanksAsync = ref.watch(blanksProvider);
    return blanksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => BlanksErrorView(
        onRetry: () => ref.invalidate(blanksProvider),
      ),
      data: (allBlanks) {
        final byId = {for (final b in allBlanks) b.id: b};
        return ListView.separated(
          itemCount: boms.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final bom = boms[index];
            final blank = byId[bom.blankId];
            return _BomRow(
              priceChipId: priceChipId,
              bom: bom,
              blankName: blank?.name ?? '#${bom.blankId}',
              blankUnit: blank?.unit ?? '',
            );
          },
        );
      },
    );
  }
}

class _BomRow extends ConsumerStatefulWidget {
  const _BomRow({
    required this.priceChipId,
    required this.bom,
    required this.blankName,
    required this.blankUnit,
  });

  final int priceChipId;
  final ProductBlankBom bom;
  final String blankName;
  final String blankUnit;

  @override
  ConsumerState<_BomRow> createState() => _BomRowState();
}

class _BomRowState extends ConsumerState<_BomRow> {
  late final TextEditingController _qtyCtrl;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: formatDouble(widget.bom.quantity));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveQuantity() async {
    final value = double.tryParse(_qtyCtrl.text.trim());
    if (value == null || value <= 0) {
      showTopSnackBar(context, BlanksLabels.messageBomInvalidQuantity);
      return;
    }
    setState(() {
      _saving = true;
      _editing = false;
    });
    try {
      await ref
          .read(bomProvider(widget.priceChipId).notifier)
          .updateBom(widget.bom.id, value);
      if (mounted) {
        showTopSnackBar(context, BlanksLabels.messageBomUpdateSuccess);
      }
    } catch (e) {
      if (mounted) showTopSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: const Text(BlanksLabels.messageDeleteConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(BlanksLabels.actionCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(BlanksLabels.actionDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref
          .read(bomProvider(widget.priceChipId).notifier)
          .removeBom(widget.bom.id);
      if (mounted) showTopSnackBar(context, BlanksLabels.messageBomDeleteSuccess);
    } catch (e) {
      if (mounted) showTopSnackBar(context, BlanksLabels.messageBomDeleteBlocked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.blankName),
      subtitle: _editing
          ? TextField(
              controller: _qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: BlanksLabels.fieldBomQuantity,
                isDense: true,
              ),
              onSubmitted: (_) => _saveQuantity(),
            )
          : Text(
              '${formatDouble(widget.bom.quantity)}'
              '${widget.blankUnit.isNotEmpty ? ' ${widget.blankUnit}' : ''}',
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editing)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: BlanksLabels.actionSave,
              onPressed: _saving ? null : _saveQuantity,
            )
          else
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: BlanksLabels.actionEdit,
              onPressed: () => setState(() => _editing = true),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: BlanksLabels.actionDeleteBom,
            onPressed: _confirmDelete,
          ),
        ],
      ),
    );
  }
}