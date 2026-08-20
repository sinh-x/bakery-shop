import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/customer_service.dart';
import '../../../data/models/customer.dart';
import 'package:bakery_app/shared/utils/diacritics.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../providers/customer_search_field_notifier.dart';
bool _matchesDiacriticAware(String query, Customer customer) {
  final q = query.trim().toLowerCase();
  final name = customer.name.trim().toLowerCase();
  if (name.contains(q)) return true;
  final hasDiacritics = q != stripDiacritics(q);
  if (!hasDiacritics) {
    if (stripDiacritics(name).contains(q)) return true;
  }
  if (customer.phone.toLowerCase().contains(q)) return true;
  for (final p in customer.phones) {
    if (p.phone.toLowerCase().contains(q)) return true;
  }
  return false;
}

class CustomerSearchField extends ConsumerStatefulWidget {
  const CustomerSearchField({
    super.key,
    this.onSelected,
    this.initialCustomer,
    this.controller,
    this.labelText,
    this.hintText,
    this.clearOnFocus = false,
  });

  final ValueChanged<Customer?>? onSelected;
  final Customer? initialCustomer;
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final bool clearOnFocus;

  @override
  ConsumerState<CustomerSearchField> createState() =>
      _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends ConsumerState<CustomerSearchField> {
  late final TextEditingController _ctrl =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  static const int _cap = CustomerSearchFieldNotifier.cap;

  @override
  void initState() {
    super.initState();
    // Deferred to a microtask so we don't mutate providers during the
    // widget-tree build phase (DG-404 Phase 4.7).
    final initialCustomer = widget.initialCustomer;
    Future.microtask(() {
      if (!mounted) return;
      ref
          .read(customerSearchFieldProvider.notifier)
          .setInitialSelected(initialCustomer);
    });
    if (initialCustomer != null) {
      _ctrl.text = initialCustomer.name;
    }
    _focus.addListener(_onFocusChange);
    // Deferred to a microtask so we don't mutate providers during the
    // widget-tree build phase (DG-404 Phase 4.7).
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (widget.controller == null) {
      _ctrl.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus && widget.clearOnFocus) {
      final notifier = ref.read(customerSearchFieldProvider.notifier);
      final state = ref.read(customerSearchFieldProvider);
      if (!state.clearedOnFocus) {
        notifier.markClearedOnFocus();
        _ctrl.clear();
        widget.onSelected?.call(null);
      }
    }
  }

  Future<void> _load() async {
    final notifier = ref.read(customerSearchFieldProvider.notifier);
    notifier.startLoad();
    try {
      final service = ref.read(customerServiceProvider);
      final customers = await service.listCustomers();
      if (!mounted) return;
      notifier.setLoadedAll(customers);
    } catch (e) {
      debugPrint('[CustomerSearch] load failed: $e');
      if (!mounted) return;
      notifier.setLoadError(CustomersLabels.customerSearchError);
    }
  }

  void _onChanged(String value) {
    final query = value.trim();
    final notifier = ref.read(customerSearchFieldProvider.notifier);
    final state = ref.read(customerSearchFieldProvider);
    if (query.isEmpty) {
      _debounce?.cancel();
      notifier.applyBrowseListForEmptyQuery();
      return;
    }

    if (state.mode == CustomerSearchFilterMode.client) {
      notifier.applyClientFilter(
        state.allCustomers
            .where((c) => _matchesDiacriticAware(query, c))
            .toList(),
      );
    } else {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 350),
        () => _search(query),
      );
    }
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    final notifier = ref.read(customerSearchFieldProvider.notifier);
    notifier.startServerSearch();
    try {
      final service = ref.read(customerServiceProvider);
      final results = await service.listCustomers(search: query);
      if (!mounted) return;
      final capped = results.take(_cap).toList();
      notifier.setServerResultsWithHint(capped, results.length > _cap);
    } catch (e) {
      debugPrint('[CustomerSearch] search failed: $e');
      if (!mounted) return;
      notifier.setServerError(CustomersLabels.customerSearchError);
    }
  }

  Future<void> _retry() async {
    final q = _ctrl.text.trim();
    final state = ref.read(customerSearchFieldProvider);
    if (state.mode == CustomerSearchFilterMode.server && q.isNotEmpty) {
      _search(q);
    } else {
      await _load();
      if (!mounted) return;
      final updated = ref.read(customerSearchFieldProvider);
      if (updated.error == null &&
          q.isNotEmpty &&
          updated.mode == CustomerSearchFilterMode.client) {
        _onChanged(_ctrl.text);
      }
    }
  }

  void _select(Customer customer) {
    ref.read(customerSearchFieldProvider.notifier).select(customer);
    widget.onSelected?.call(customer);
  }

  Widget _errorView() {
    final theme = Theme.of(context);
    final error = ref.watch(customerSearchFieldProvider).error;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 32,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text(SharedLabels.retry),
          ),
        ],
      ),
    );
  }

  Widget _resultsList() {
    final theme = Theme.of(context);
    final state = ref.watch(customerSearchFieldProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: state.listCustomers.length,
            itemBuilder: (context, index) {
              final c = state.listCustomers[index];
              return ListTile(
                dense: true,
                title: Text(c.name),
                subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                onTap: () => _select(c),
              );
            },
          ),
        ),
        if (state.selected != null)
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
                    CustomersLabels.customerSearchLinked.replaceAll(
                      '{name}',
                      state.selected!.name,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (state.showRefineHint)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              CustomersLabels.customerSearchRefineHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(customerSearchFieldProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.labelText ?? OrdersLabels.customer,
            hintText: widget.hintText ?? CustomersLabels.customerSearchHint,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_search_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
                  ? _errorView()
                  : state.listCustomers.isEmpty
                      ? Center(
                          child: Text(
                            CustomersLabels.customerSearchNoMatch,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                      : _resultsList(),
        ),
      ],
    );
  }
}