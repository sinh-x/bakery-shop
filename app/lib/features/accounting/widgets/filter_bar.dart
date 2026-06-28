import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/account.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

/// Filter bar for the accounting journal tab.
///
/// Extracted from journal_tab.dart (DG-189 Phase 1, finding M-2). Hosts the
/// since/until date chips, account dropdown, source-type dropdown, and lock
/// button. All state is hoisted to the caller via callbacks.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.since,
    required this.until,
    required this.sourceType,
    required this.accountsAsync,
    required this.accountId,
    required this.onSinceChanged,
    required this.onUntilChanged,
    required this.onSourceTypeChanged,
    required this.onAccountChanged,
    required this.onLock,
  });

  final String? since;
  final String? until;
  final String? sourceType;
  final AsyncValue<List<Account>> accountsAsync;
  final int? accountId;
  final ValueChanged<String?> onSinceChanged;
  final ValueChanged<String?> onUntilChanged;
  final ValueChanged<String?> onSourceTypeChanged;
  final ValueChanged<int?> onAccountChanged;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DateChip(
            label: VN.accountingFilterSince,
            value: since,
            onSelected: onSinceChanged,
          ),
          DateChip(
            label: VN.accountingFilterUntil,
            value: until,
            onSelected: onUntilChanged,
          ),
          accountsAsync.when(
            loading: () => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (accounts) => DropdownButton<int?>(
              value: accountId,
              hint: const Text(VN.accountingFilterAccount),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text(VN.accountingFilterAccount),
                ),
                ...accounts.map(
                  (a) => DropdownMenuItem<int?>(
                    value: int.tryParse(a.id),
                    child: Text('${a.code} — ${a.name}'),
                  ),
                ),
              ],
              onChanged: onAccountChanged,
            ),
          ),
          DropdownButton<String?>(
            value: sourceType,
            hint: const Text(VN.accountingFilterSourceType),
            items: const [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(VN.accountingSourceTypeAll),
              ),
              DropdownMenuItem<String?>(
                value: 'expense',
                child: Text(VN.accountingSourceTypeExpense),
              ),
              DropdownMenuItem<String?>(
                value: 'payment_transaction',
                child: Text(VN.accountingSourceTypePayment),
              ),
              DropdownMenuItem<String?>(
                value: 'order',
                child: Text(VN.accountingSourceTypeOrder),
              ),
              DropdownMenuItem<String?>(
                value: 'order_cogs',
                child: Text(VN.accountingSourceTypeCogs),
              ),
              DropdownMenuItem<String?>(
                value: 'order_shipping_hold',
                child: Text(VN.accountingSourceTypeShippingHold),
              ),
              DropdownMenuItem<String?>(
                value: 'order_shipping_release',
                child: Text(VN.accountingSourceTypeShippingRelease),
              ),
              DropdownMenuItem<String?>(
                value: 'owner_capital',
                child: Text(VN.accountingOwnerCapital),
              ),
              DropdownMenuItem<String?>(
                value: 'owner_draw',
                child: Text(VN.accountingOwnerDraw),
              ),
              DropdownMenuItem<String?>(
                value: 'staff_reimburse',
                child: Text(VN.accountingStaffReimburse),
              ),
            ],
            onChanged: onSourceTypeChanged,
          ),
          FilledButton.tonalIcon(
            onPressed: onLock,
            icon: const Icon(Icons.lock_outline),
            label: const Text(VN.accountingLockJournal),
          ),
        ],
      ),
    );
  }
}

/// Date-picker chip used by [FilterBar] for since/until date selection.
class DateChip extends StatelessWidget {
  const DateChip({
    super.key,
    required this.label,
    required this.value,
    required this.onSelected,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(value == null ? label : '$label: $value'),
      avatar: const Icon(Icons.calendar_today, size: 16),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null) {
          onSelected(
            formatDisplay(picked, pattern: 'yyyy-MM-dd'),
          );
        }
      },
    );
  }
}