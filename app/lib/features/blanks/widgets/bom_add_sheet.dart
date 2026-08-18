import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/blanks_provider.dart';
import '../../../data/providers/bom_provider.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Show the add-BOM-mapping bottom sheet for [priceChipId].
///
/// The sheet lists available blanks (excluding any already mapped to this
/// price chip) in a dropdown, plus a quantity field. On save it calls
/// `BomNotifier.addBom` and dismisses.
Future<void> showBomAddSheet(BuildContext context, int priceChipId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _BomAddSheet(priceChipId: priceChipId),
  );
}

class _BomAddSheet extends ConsumerStatefulWidget {
  const _BomAddSheet({required this.priceChipId});

  final int priceChipId;

  @override
  ConsumerState<_BomAddSheet> createState() => _BomAddSheetState();
}

class _BomAddSheetState extends ConsumerState<_BomAddSheet> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController(text: '1');
  int? _selectedBlankId;
  bool _saving = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBlankId == null) {
      showTopSnackBar(context, BlanksLabels.messageBomSelectBlank);
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      showTopSnackBar(context, BlanksLabels.messageBomInvalidQuantity);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(bomProvider(widget.priceChipId).notifier)
          .addBom(_selectedBlankId!, qty);
      if (mounted) {
        Navigator.of(context).pop();
        showTopSnackBar(context, BlanksLabels.messageBomCreateSuccess);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTopSnackBar(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final blanksAsync = ref.watch(blanksProvider);
    final bomAsync = ref.watch(bomProvider(widget.priceChipId));
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: blanksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Text(SharedLabels.apiError),
        data: (blanks) {
          final mappedIds = bomAsync.maybeWhen(
            data: (boms) => boms.map((b) => b.blankId).toSet(),
            orElse: () => <int>{},
          );
          final available = blanks.where((b) => !mappedIds.contains(b.id)).toList();
          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    BlanksLabels.actionAddBom,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedBlankId,
                    decoration: const InputDecoration(
                      labelText: BlanksLabels.fieldBlank,
                      border: OutlineInputBorder(),
                    ),
                    items: available
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.name),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _selectedBlankId = v),
                    validator: (v) =>
                        v == null ? BlanksLabels.messageBomSelectBlank : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: BlanksLabels.fieldBomQuantity,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      return (n == null || n <= 0)
                          ? BlanksLabels.messageBomInvalidQuantity
                          : null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text(BlanksLabels.actionCancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(BlanksLabels.actionSave),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
