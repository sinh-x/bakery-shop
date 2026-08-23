import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/blanks_provider.dart';
import '../../../data/providers/bom_provider.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../providers/bom_add_sheet_notifier.dart';

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
  late final TextEditingController _qtyCtrl;

  FormDraftContext get _draftContext => bomAddDraftContext(widget.priceChipId);

  @override
  void initState() {
    super.initState();
    final draft = ref.read(bomAddSheetProvider(_draftContext));
    _qtyCtrl = TextEditingController(text: draft.quantity)
      ..addListener(_persistQuantity);
  }

  void _persistQuantity() => ref
      .read(bomAddSheetProvider(_draftContext).notifier)
      .setQuantity(_qtyCtrl.text);

  @override
  void dispose() {
    _qtyCtrl.removeListener(_persistQuantity);
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final selectedBlankId = ref
        .read(bomAddSheetProvider(_draftContext))
        .selectedBlankId;
    if (selectedBlankId == null) {
      showTopSnackBar(context, BlanksLabels.messageBomSelectBlank);
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      showTopSnackBar(context, BlanksLabels.messageBomInvalidQuantity);
      return;
    }
    final draftNotifier = ref.read(bomAddSheetProvider(_draftContext).notifier);
    final submittedDraft = draftNotifier.retainedDraft;
    draftNotifier.setSaving(true);
    try {
      await ref
          .read(bomProvider(widget.priceChipId).notifier)
          .addBom(selectedBlankId, qty);
      draftNotifier.completeSuccess(submittedDraft);
      if (mounted) {
        Navigator.of(context).pop();
        showTopSnackBar(context, BlanksLabels.messageBomCreateSuccess);
      }
    } catch (e) {
      draftNotifier.setSaving(false);
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final blanksAsync = ref.watch(blanksProvider);
    final bomAsync = ref.watch(bomProvider(widget.priceChipId));
    final sheetState = ref.watch(bomAddSheetProvider(_draftContext));
    final selectedBlankId = sheetState.selectedBlankId;
    final saving = sheetState.saving;
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
          final available = blanks
              .where((b) => !mappedIds.contains(b.id))
              .toList();
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
                    key: ValueKey(
                      'bom-blank-${widget.priceChipId}-$selectedBlankId',
                    ),
                    initialValue: selectedBlankId,
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
                    onChanged: saving
                        ? null
                        : (v) => ref
                              .read(bomAddSheetProvider(_draftContext).notifier)
                              .selectBlank(v),
                    validator: (v) =>
                        v == null ? BlanksLabels.messageBomSelectBlank : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                  DiscardFormDraftAction(
                    isDirty:
                        selectedBlankId != null || sheetState.quantity != '1',
                    onDiscard: () {
                      _qtyCtrl.text = '1';
                      ref
                          .read(bomAddSheetProvider(_draftContext).notifier)
                          .clear();
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text(BlanksLabels.actionCancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: saving ? null : _save,
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
