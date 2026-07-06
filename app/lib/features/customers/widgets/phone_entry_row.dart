import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bakery_app/shared/labels/customers.dart';

/// A single editable phone row (controller + primary flag).
///
/// Extracted from `customer_form.dart` (DG-205 review-auto Mn-1) to keep the
/// form file under the 400-line threshold. The controller is owned by the
/// caller; [PhoneEntry] only holds the state and disposes the controller.
class PhoneEntry {
  PhoneEntry({required this.controller, this.isPrimary = false});

  final TextEditingController controller;
  bool isPrimary;

  void dispose() => controller.dispose();
}

/// A single phone row: text field + primary radio + remove button.
///
/// Renders one entry in the multi-phone list inside the customer form. The
/// caller owns the [PhoneEntry] and drives add/remove/primary actions via the
/// callbacks so the parent [State] stays the single source of truth.
class PhoneEntryRow extends StatelessWidget {
  const PhoneEntryRow({
    super.key,
    required this.entry,
    required this.canRemove,
    required this.onRemove,
    required this.onSetPrimary,
  });

  final PhoneEntry entry;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onSetPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: entry.controller,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                LengthLimitingTextInputFormatter(20),
              ],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: VN.customerPhoneField,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Primary radio toggle. Selecting this row deselects all others.
          Tooltip(
            message: VN.customerPrimaryPhone,
            child: IconButton(
              onPressed: onSetPrimary,
              icon: Icon(
                entry.isPrimary ? Icons.star : Icons.star_border,
              ),
              color: entry.isPrimary
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            onPressed: canRemove ? onRemove : null,
            tooltip: VN.customerRemovePhone,
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }
}