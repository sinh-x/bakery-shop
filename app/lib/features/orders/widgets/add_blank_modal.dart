import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/blank.dart';
import '../../../data/providers/blanks_provider.dart';
import '../../../shared/labels/blanks.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

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
    ),
  );
}

class _AddBlankModal extends ConsumerStatefulWidget {
  const _AddBlankModal({
    this.initialBlankId,
    this.initialQuantity = 1.0,
    this.initialNotes = '',
    this.isEdit = false,
  });

  final int? initialBlankId;
  final double initialQuantity;
  final String initialNotes;
  final bool isEdit;

  @override
  ConsumerState<_AddBlankModal> createState() => _AddBlankModalState();
}

class _AddBlankModalState extends ConsumerState<_AddBlankModal> {
  int? _blankId;
  late final TextEditingController _qtyController;
  late final TextEditingController _notesController;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _blankId = widget.initialBlankId;
    _qtyController = TextEditingController(
      text: widget.initialQuantity == widget.initialQuantity.roundToDouble()
          ? widget.initialQuantity.toInt().toString()
          : widget.initialQuantity.toString(),
    );
    _notesController = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _qty => double.tryParse(_qtyController.text.trim()) ?? 0.0;

  bool get _hasBlankError => _submitted && _blankId == null;
  bool get _hasQtyError =>
      _submitted && (_qty <= 0 || !_isFinitePositive(_qty));

  static bool _isFinitePositive(double v) =>
      v.isFinite && v > 0;

  void _submit() {
    setState(() => _submitted = true);
    if (_blankId == null || _qty <= 0 || !_isFinitePositive(_qty)) return;
    Navigator.of(context).pop(
      BlankModalResult(
        blankId: _blankId!,
        quantity: _qty,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blanksAsync = ref.watch(blanksProvider);
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
                    '${VN.apiError}: $e',
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
      widget.isEdit
          ? BlanksLabels.editBlankTitle
          : BlanksLabels.addBlankTitle,
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildForm(BuildContext context, List<Blank> blanks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _blankId,
          decoration: InputDecoration(
            labelText: BlanksLabels.fieldBlankSelect,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _hasBlankError ? BlanksLabels.messageBlankRequired : null,
          ),
          items: blanks
              .map(
                (b) => DropdownMenuItem<int>(
                  value: b.id,
                  child: Text(b.name),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() {
            _blankId = v;
            _submitted = false;
          }),
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
            errorText:
                _hasQtyError ? BlanksLabels.messageBlankQuantityInvalid : null,
          ),
          onChanged: (_) {
            if (_submitted) setState(() => _submitted = false);
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
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(VN.cancel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: _submit,
            child: const Text(VN.xacNhan),
          ),
        ),
      ],
    );
  }
}