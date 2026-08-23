import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/blank.dart';
import '../../../data/providers/blank_stock_provider.dart';
import '../../../shared/utils/format_double.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import '../providers/blank_stock_action_sheet_notifier.dart';

/// Type of stock movement being recorded.
enum BlankStockAction { production, usage }

/// Show the bottom sheet to record a blank stock movement (nhập/xuất kho).
///
/// [summary] is the row being acted on (provides blankId, name, unit). The
/// sheet collects quantity, optional producedDate (production only), and
/// optional expiryDate, then calls the matching notifier method and
/// dismisses. Validation: quantity > 0.
Future<void> showBlankStockActionSheet(
  BuildContext context,
  BlankStockSummary summary,
  BlankStockAction action,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BlankStockActionSheet(summary: summary, action: action),
  );
}

class _BlankStockActionSheet extends ConsumerStatefulWidget {
  const _BlankStockActionSheet({required this.summary, required this.action});

  final BlankStockSummary summary;
  final BlankStockAction action;

  @override
  ConsumerState<_BlankStockActionSheet> createState() =>
      _BlankStockActionSheetState();
}

class _BlankStockActionSheetState
    extends ConsumerState<_BlankStockActionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _producedCtrl;
  late final TextEditingController _expiryCtrl;

  FormDraftContext get _draftContext => blankStockActionDraftContext(
    blankId: widget.summary.blankId,
    action: widget.action.name,
  );

  @override
  void initState() {
    super.initState();
    final draft = ref.read(blankStockActionSheetProvider(_draftContext));
    _qtyCtrl = TextEditingController(text: draft.quantity)
      ..addListener(_persistQuantity);
    _producedCtrl = TextEditingController(text: draft.producedDate)
      ..addListener(_persistProducedDate);
    _expiryCtrl = TextEditingController(text: draft.expiryDate)
      ..addListener(_persistExpiryDate);
  }

  void _persistQuantity() => ref
      .read(blankStockActionSheetProvider(_draftContext).notifier)
      .setQuantity(_qtyCtrl.text);

  void _persistProducedDate() => ref
      .read(blankStockActionSheetProvider(_draftContext).notifier)
      .setProducedDate(_producedCtrl.text);

  void _persistExpiryDate() => ref
      .read(blankStockActionSheetProvider(_draftContext).notifier)
      .setExpiryDate(_expiryCtrl.text);

  @override
  void dispose() {
    _qtyCtrl.removeListener(_persistQuantity);
    _producedCtrl.removeListener(_persistProducedDate);
    _expiryCtrl.removeListener(_persistExpiryDate);
    _qtyCtrl.dispose();
    _producedCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  String get _title => widget.action == BlankStockAction.production
      ? BlanksLabels.actionStockIn
      : BlanksLabels.actionStockOut;

  bool get _isProduction => widget.action == BlankStockAction.production;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final qty = double.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      showTopSnackBar(context, BlanksLabels.messageStockInvalidQuantity);
      return;
    }
    final draftNotifier = ref.read(
      blankStockActionSheetProvider(_draftContext).notifier,
    );
    final submittedDraft = draftNotifier.retainedDraft;
    draftNotifier.setSaving(true);
    try {
      final notifier = ref.read(blankStockProvider.notifier);
      if (_isProduction) {
        await notifier.recordProduction(
          widget.summary.blankId,
          qty,
          producedDate: _producedCtrl.text.trim(),
          expiryDate: _expiryCtrl.text.trim().isEmpty
              ? null
              : _expiryCtrl.text.trim(),
        );
      } else {
        await notifier.recordUsage(
          widget.summary.blankId,
          qty,
          producedDate: _producedCtrl.text.trim(),
        );
      }
      draftNotifier.completeSuccess(submittedDraft);
      if (mounted) {
        Navigator.of(context).pop();
        showTopSnackBar(context, BlanksLabels.messageStockRecordSuccess);
      }
    } catch (e) {
      draftNotifier.setSaving(false);
      if (mounted) {
        showTopSnackBar(context, BlanksLabels.messageStockRecordFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetState = ref.watch(blankStockActionSheetProvider(_draftContext));
    final saving = sheetState.saving;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '${widget.summary.name}'
                '${widget.summary.unit.isNotEmpty ? ' (${widget.summary.unit})' : ''}'
                ' — ${BlanksLabels.demandStock}: ${formatDouble(widget.summary.stock)}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: BlanksLabels.fieldQuantity,
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return (n == null || n <= 0)
                      ? BlanksLabels.messageStockInvalidQuantity
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _producedCtrl,
                decoration: const InputDecoration(
                  labelText: BlanksLabels.fieldProducedDate,
                  hintText: 'YYYY-MM-DD',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_isProduction) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _expiryCtrl,
                  decoration: const InputDecoration(
                    labelText: BlanksLabels.fieldExpiryDateOptional,
                    hintText: 'YYYY-MM-DD',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              DiscardFormDraftAction(
                isDirty:
                    sheetState.quantity != '1' ||
                    sheetState.producedDate.isNotEmpty ||
                    sheetState.expiryDate.isNotEmpty,
                onDiscard: () {
                  _qtyCtrl.text = '1';
                  _producedCtrl.clear();
                  _expiryCtrl.clear();
                  ref
                      .read(
                        blankStockActionSheetProvider(_draftContext).notifier,
                      )
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
                    onPressed: saving ? null : _submit,
                    child: saving
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
      ),
    );
  }
}
