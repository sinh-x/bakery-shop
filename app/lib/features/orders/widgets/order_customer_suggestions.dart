import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/customer_service.dart';
import '../../../data/models/customer.dart';
import 'package:bakery_app/shared/labels/customers.dart';

/// Inline customer suggestions shown while typing a name or phone in the
/// order form (DG-252 Phase 5 — FR4/NFR4/AC2).
///
/// Listens to both [nameCtrl] and [phoneCtrl]. When either field accumulates
/// ≥2 characters, this widget debounces 350 ms (NFR4), queries the backend
/// `GET /api/customers?search=` endpoint (diacritic-insensitive) via
/// [CustomerService.listCustomers], caps results at
/// [CustomersLabels.orderSuggestionsCap] rows (NFR4), and renders an inline
/// list. Tapping a row calls [onSelected] so the parent can set
/// `selectedCustomer` and fill the name/phone fields (tap-to-link, FR4).
///
/// Suggestions are hidden when the query length drops below 2, the selected
/// customer matches the current text, or the parent reports no name/phone
/// controllers.
class OrderCustomerSuggestions extends ConsumerStatefulWidget {
  const OrderCustomerSuggestions({
    super.key,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.onSelected,
    this.selectedCustomer,
  });

  /// Name field controller — its text drives suggestions alongside [phoneCtrl].
  final TextEditingController nameCtrl;

  /// Phone field controller — its text drives suggestions alongside [nameCtrl].
  final TextEditingController phoneCtrl;

  /// Called when a suggestion is tapped. The parent fills `selectedCustomer`
  /// and the name/phone fields from the chosen [Customer] (tap-to-link).
  final ValueChanged<Customer> onSelected;

  /// Currently linked customer. When its name matches the name field text,
  /// suggestions are hidden to avoid re-prompting on a fresh selection.
  final Customer? selectedCustomer;

  @override
  ConsumerState<OrderCustomerSuggestions> createState() =>
      _OrderCustomerSuggestionsState();
}

class _OrderCustomerSuggestionsState
    extends ConsumerState<OrderCustomerSuggestions> {
  Timer? _debounce;
  List<Customer> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  bool _showRefineHint = false;

  @override
  void initState() {
    super.initState();
    widget.nameCtrl.addListener(_onFieldChanged);
    widget.phoneCtrl.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.nameCtrl.removeListener(_onFieldChanged);
    widget.phoneCtrl.removeListener(_onFieldChanged);
    super.dispose();
  }

  String _effectiveQuery() {
    final name = widget.nameCtrl.text.trim();
    final phone = widget.phoneCtrl.text.trim();
    final stripped = phone.replaceAll(RegExp(r'[\s-]'), '');
    final query = name.length >= stripped.length ? name : stripped;
    if (query.length < 2) return '';
    return query;
  }

  void _onFieldChanged() {
    final query = _effectiveQuery();
    if (query.isEmpty) {
      _debounce?.cancel();
      _clearResults();
      return;
    }
    if (widget.selectedCustomer != null &&
        _matchesSelected(widget.selectedCustomer!, query)) {
      _debounce?.cancel();
      _clearResults();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  bool _matchesSelected(Customer customer, String query) {
    final q = query.toLowerCase();
    final name = customer.name.trim().toLowerCase();
    if (name.contains(q)) return true;
    final phone = customer.phone.toLowerCase();
    final strippedPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
    if (strippedPhone.contains(q)) return true;
    return false;
  }

  void _clearResults() {
    if (!mounted) return;
    setState(() {
      _results = const [];
      _loading = false;
      _searched = false;
      _error = null;
      _showRefineHint = false;
    });
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(customerServiceProvider);
      final results = await service.listCustomers(search: query);
      if (!mounted) return;
      const cap = CustomersLabels.orderSuggestionsCap;
      final capped = results.take(cap).toList();
      setState(() {
        _results = capped;
        _showRefineHint = results.length > cap;
        _loading = false;
        _searched = true;
      });
    } catch (e) {
      debugPrint('[OrderCustomerSuggestions] search failed: $e');
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
        _error = CustomersLabels.orderSuggestionsError;
        _showRefineHint = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _effectiveQuery();
    if (query.isEmpty) {
      _debounce?.cancel();
      return const SizedBox.shrink();
    }
    if (_error != null) {
      return _errorView(context);
    }
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              CustomersLabels.orderSuggestionsLoading,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      // Only surface the no-match label after a search has actually run,
      // so the widget does not flash "no match" before the first debounce.
      if (!_searched) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const Icon(Icons.search_off, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                CustomersLabels.orderSuggestionsNoMatch,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    return _resultsList(context);
  }

  Widget _errorView(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          TextButton.icon(
            onPressed: () => _search(_effectiveQuery()),
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text(CustomersLabels.orderSuggestionsRetry),
          ),
        ],
      ),
    );
  }

  Widget _resultsList(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              CustomersLabels.orderSuggestionsHint,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (final c in _results)
                  ListTile(
                    dense: true,
                    title: Text(c.name),
                    subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                    onTap: () {
                      _debounce?.cancel();
                      widget.onSelected(c);
                      _clearResults();
                    },
                  ),
              ],
            ),
          ),
          if (_showRefineHint)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                CustomersLabels.orderSuggestionsRefineHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}