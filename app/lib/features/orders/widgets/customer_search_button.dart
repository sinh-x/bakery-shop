import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';
import '../../customers/widgets/customer_search_field.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Customer search modal host (DG-218 Phase 1 — FR-8).
///
/// Replaces the inline `CustomerSearchField` in Stage 2 of create/edit/POS
/// with a "Tìm khách hàng" button that opens a modal dialog hosting the
/// existing [CustomerSearchField] (diacritic-aware, 350ms debounce). The
/// search logic itself is unchanged — this widget only wraps the field in a
/// modal presentation so the search entry is visually distinct from the
/// name/phone input fields below it.
///
/// Selecting a result fills the customer name/phone and closes the modal.
class CustomerSearchButton extends ConsumerWidget {
  const CustomerSearchButton({
    super.key,
    this.selectedCustomer,
    this.onSelected,
  });

  final Customer? selectedCustomer;
  final ValueChanged<Customer?>? onSelected;

  Future<void> _openModal(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Customer?>(
      context: context,
      builder: (dialogContext) => _CustomerSearchModal(
        initialCustomer: selectedCustomer,
      ),
    );
    if (result != null) {
      onSelected?.call(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: () => _openModal(context, ref),
        icon: const Icon(Icons.person_search_outlined, size: 20),
        label: const Text(OrdersLabels.customerSearchButton),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          foregroundColor: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Modal dialog hosting [CustomerSearchField] (DG-218 Phase 1 — FR-8).
///
/// The search field keeps its overlay-based suggestions inside the dialog.
/// Tapping a result calls [onSelected] and closes the dialog, returning the
/// selected [Customer] to the caller.
class _CustomerSearchModal extends ConsumerStatefulWidget {
  const _CustomerSearchModal({this.initialCustomer});

  final Customer? initialCustomer;

  @override
  ConsumerState<_CustomerSearchModal> createState() =>
      _CustomerSearchModalState();
}

class _CustomerSearchModalState extends ConsumerState<_CustomerSearchModal> {
  Customer? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCustomer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.person_search_outlined, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text(OrdersLabels.customerSearchModalTitle)),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomerSearchField(
                initialCustomer: _selected,
                onSelected: (customer) {
                  if (customer != null) {
                    Navigator.of(context).pop(customer);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          VN.customerSearchLinked.replaceAll(
                            '{name}',
                            _selected!.name,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
      ],
    );
  }
}