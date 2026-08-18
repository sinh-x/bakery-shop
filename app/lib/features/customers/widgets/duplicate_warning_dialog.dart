import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/customers.dart';

import '../../../data/models/customer.dart';

/// Choice returned by the duplicate-warning dialog (FR8/AC6).
///
/// Either [useExisting] is set (the user picked an existing customer) or
/// [createAnyway] is true (the user chose to proceed with the new create).
typedef DuplicateChoice = ({Customer? useExisting, bool createAnyway});

/// Duplicate-warning dialog shown before a manual customer create when the
/// typed name or any phone matches an existing customer (DG-252 Phase 6 —
/// FR8/AC6). Lists each match with name + primary phone and offers three
/// actions: "use existing" (selects a match), "create anyway" (proceeds
/// with the create), or cancel.
///
/// Extracted from `customer_form.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class DuplicateWarningDialog extends StatelessWidget {
  const DuplicateWarningDialog({super.key, required this.matches});

  final List<Customer> matches;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(CustomersLabels.duplicateWarningTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(CustomersLabels.duplicateWarningHint),
            const SizedBox(height: 12),
            for (final c in matches)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(c.name),
                subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                onTap: () => Navigator.of(context).pop<DuplicateChoice>(
                  (useExisting: c, createAnyway: false),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(CustomersLabels.duplicateWarningCancel),
        ),
        FilledButton.tonal(
          onPressed: matches.isEmpty
              ? null
              : () => Navigator.of(context).pop<DuplicateChoice>(
                    (useExisting: matches.first, createAnyway: false),
                  ),
          child: const Text(CustomersLabels.duplicateWarningUseExisting),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop<DuplicateChoice>(
            const (useExisting: null, createAnyway: true),
          ),
          child: const Text(CustomersLabels.duplicateWarningCreateAnyway),
        ),
      ],
    );
  }
}