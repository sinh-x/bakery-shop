import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/blank.dart';
import '../../../data/providers/blanks_provider.dart';
import '../providers/add_blank_modal_notifier.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/labels/blanks.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Result of the add/edit blank modal (DG-294 FR3-FR5).
///
/// Carries the user-entered values back to [CakeDetailScreen] which then
/// invokes the matching `OrderWorkItemsNotifier` blank CRUD method.
class BlankModalResult {
  const BlankModalResult({
    required this.blankId,
    required this.quantity,
    required this.notes,
  });

  final int blankId;
  final double quantity;
  final String notes;
}

/// Opens the add/edit blank modal bottom sheet for a work item (DG-294 FR3).
///
/// When [editing] is non-null the modal is pre-filled with the existing
/// assignment's values (FR5 edit flow). Returns the confirmed
/// [BlankModalResult] or `null` when the user cancels.
Future<BlankModalResult?> showAddBlankModal(
  BuildContext context, {

  /// Pre-selected blank id when editing (FR5), `null` when adding.
  int? initialBlankId,

  /// Initial quantity (defaults to 1 for add, prefilled for edit).
  double initialQuantity = 1.0,

  /// Initial notes (empty for add, prefilled for edit).
  String initialNotes = '',

  /// When true, the title shows the edit label (FR5).
  bool isEdit = false,
  required FormDraftContext draftContext,
}) {
  return showModalBottomSheet<BlankModalResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddBlankModal(
      initialBlankId: initialBlankId,
      initialQuantity: initialQuantity,
      initialNotes: initialNotes,
      isEdit: isEdit,
      draftContext: draftContext,
    ),
  );
}

class _AddBlankModal extends ConsumerStatefulWidget {
  const _AddBlankModal({
    this.initialBlankId,
    this.initialQuantity = 1.0,
    this.initialNotes = '',
    this.isEdit = false,
    required this.draftContext,
  });

  final int? initialBlankId;
  final double initialQuantity;
  final String initialNotes;
  final bool isEdit;
  final FormDraftContext draftContext;

  @override
  ConsumerState<_AddBlankModal> createState() => _AddBlankModalState();
}

class _AddBlankModalState extends ConsumerState<_AddBlankModal> {
  late final TextEditingController _qtyController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    // Defer the seed to avoid modifying a provider during the build phase.
    Future.microtask(() {
      if (mounted) {
        ref
            .read(addBlankModalProvider(widget.draftContext).notifier)
            .seed(
              blankId: widget.initialBlankId,
              quantity: _formatQuantity(widget.initialQuantity),
              notes: widget.initialNotes,
            );
      }
    });
    final draft = ref.read(addBlankModalProvider(widget.draftContext));
    final hasDraft = ref
        .read(formDraftSessionProvider)
        .containsKey(widget.draftContext);
    _qtyController = TextEditingController(
      text: hasDraft ? draft.quantity : _formatQuantity(widget.initialQuantity),
    )..addListener(_persistQuantity);
    _notesController = TextEditingController(
      text: hasDraft ? draft.notes : widget.initialNotes,
    )..addListener(_persistNotes);
  }

  static String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  void _persistQuantity() => ref
      .read(addBlankModalProvider(widget.draftContext).notifier)
      .setQuantity(_qtyController.text);

  void _persistNotes() => ref
      .read(addBlankModalProvider(widget.draftContext).notifier)
      .setNotes(_notesController.text);

  @override
  void dispose() {
    _qtyController.removeListener(_persistQuantity);
    _notesController.removeListener(_persistNotes);
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _qty => double.tryParse(_qtyController.text.trim()) ?? 0.0;

  static bool _isFinitePositive(double v) => v.isFinite && v > 0;

  void _submit() {
    final provider = addBlankModalProvider(widget.draftContext);
    ref.read(provider.notifier).setSubmitted();
    final s = ref.read(provider);
    if (s.blankId == null || _qty <= 0 || !_isFinitePositive(_qty)) return;
    Navigator.of(context).pop(
      BlankModalResult(
        blankId: s.blankId!,
        quantity: _qty,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blanksAsync = ref.watch(blanksProvider);
    // Watch so the form rebuilds when blankId/submitted change.
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
              _buildHandle(context),
              const SizedBox(height: 12),
              _buildTitle(context),
              const SizedBox(height: 16),
              blanksAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    '${SharedLabels.apiError}: $e',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                data: (blanks) => _buildForm(context, blanks),
              ),
              const SizedBox(height: 16),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      widget.isEdit ? BlanksLabels.editBlankTitle : BlanksLabels.addBlankTitle,
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildForm(BuildContext context, List<Blank> blanks) {
    final modalState = ref.watch(addBlankModalProvider(widget.draftContext));
    final blankId = modalState.blankId;
    final submitted = modalState.submitted;
    final hasBlankError = submitted && blankId == null;
    final hasQtyError = submitted && (_qty <= 0 || !_isFinitePositive(_qty));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: blankId,
          decoration: InputDecoration(
            labelText: BlanksLabels.fieldBlankSelect,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: hasBlankError ? BlanksLabels.messageBlankRequired : null,
          ),
          items: blanks
              .map(
                (b) => DropdownMenuItem<int>(value: b.id, child: Text(b.name)),
              )
              .toList(),
          onChanged: (v) => ref
              .read(addBlankModalProvider(widget.draftContext).notifier)
              .setBlankId(v),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _qtyController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: BlanksLabels.fieldBlankQuantity,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: hasQtyError
                ? BlanksLabels.messageBlankQuantityInvalid
                : null,
          ),
          onChanged: (_) {
            if (ref
                .read(addBlankModalProvider(widget.draftContext))
                .submitted) {
              ref
                  .read(addBlankModalProvider(widget.draftContext).notifier)
                  .clearSubmitted();
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: BlanksLabels.fieldBlankNotes,
            hintText: BlanksLabels.fieldBlankNotesHint,
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        DiscardFormDraftAction(
          isDirty: ref
              .watch(addBlankModalProvider(widget.draftContext))
              .isDirty,
          onDiscard: () {
            ref
                .read(addBlankModalProvider(widget.draftContext).notifier)
                .clearDraft();
            Navigator.of(context).pop();
          },
        ),
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(SharedLabels.cancel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: _submit,
            child: const Text(OrdersLabels.xacNhan),
          ),
        ),
      ],
    );
  }
}
