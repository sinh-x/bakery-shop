import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/blanks_provider.dart';
import 'package:bakery_app/shared/labels/blanks.dart';

/// Blank (phôi) assignment dropdown shown on the work item edit card.
///
/// Watches [blanksProvider] for the list of available blanks and invokes
/// [onChanged] whenever the user selects a different blank (or clears the
/// assignment by picking the "none" entry). The parent wires [onChanged] to
/// the existing focus-loss auto-save PATCH so the selection persists
/// immediately (DG-293 FR8 / AC2).
class WorkItemBlankDropdown extends ConsumerWidget {
  const WorkItemBlankDropdown({
    super.key,
    required this.blankId,
    required this.onChanged,
  });

  /// Current `blankId` of the work item (`null` means no blank assigned).
  final int? blankId;

  /// Called with the newly selected blank id, or `null` when cleared.
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blanksAsync = ref.watch(blanksProvider);
    return blanksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (blanks) {
        if (blanks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DropdownButtonFormField<int?>(
            initialValue: blanks.any((b) => b.id == blankId) ? blankId : null,
            decoration: const InputDecoration(
              labelText: BlanksLabels.fieldBlank,
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text(BlanksLabels.notAssigned),
              ),
              ...blanks.map(
                (b) => DropdownMenuItem<int?>(
                  value: b.id,
                  child: Text(b.name),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}