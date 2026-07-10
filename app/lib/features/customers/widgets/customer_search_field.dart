import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/customer_service.dart';
import '../../../data/models/customer.dart';
import 'package:bakery_app/shared/labels/customers.dart';

String _stripDiacritics(String s) {
  const diacriticMap = {
    'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
    'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
    'đ': 'd',
    'À': 'A', 'Á': 'A', 'Ả': 'A', 'Ã': 'A', 'Ạ': 'A',
    'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ẳ': 'A', 'Ẵ': 'A', 'Ặ': 'A',
    'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ẩ': 'A', 'Ẫ': 'A', 'Ậ': 'A',
    'È': 'E', 'É': 'E', 'Ẻ': 'E', 'Ẽ': 'E', 'Ẹ': 'E',
    'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ể': 'E', 'Ễ': 'E', 'Ệ': 'E',
    'Ì': 'I', 'Í': 'I', 'Ỉ': 'I', 'Ĩ': 'I', 'Ị': 'I',
    'Ò': 'O', 'Ó': 'O', 'Ỏ': 'O', 'Õ': 'O', 'Ọ': 'O',
    'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ổ': 'O', 'Ỗ': 'O', 'Ộ': 'O',
    'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ở': 'O', 'Ỡ': 'O', 'Ợ': 'O',
    'Ù': 'U', 'Ú': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ụ': 'U',
    'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ử': 'U', 'Ữ': 'U', 'Ự': 'U',
    'Ỳ': 'Y', 'Ý': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Ỵ': 'Y',
    'Đ': 'D',
  };
  return s.split('').map((c) => diacriticMap[c] ?? c).join();
}

bool _matchesDiacriticAware(String query, Customer customer) {
  final q = query.trim().toLowerCase();
  final name = customer.name.trim().toLowerCase();
  if (name.contains(q)) return true;
  final hasDiacritics = q != _stripDiacritics(q);
  if (!hasDiacritics) {
    if (_stripDiacritics(name).contains(q)) return true;
  }
  if (customer.phone.toLowerCase().contains(q)) return true;
  for (final p in customer.phones) {
    if (p.phone.toLowerCase().contains(q)) return true;
  }
  return false;
}

enum _FilterMode { client, server }

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

  List<Customer> _allCustomers = const [];
  List<Customer> _listCustomers = const [];
  _FilterMode _mode = _FilterMode.client;
  bool _loading = false;
  Customer? _selected;
  bool _clearedOnFocus = false;
  String? _error;
  bool _showRefineHint = false;

  static const int _cap = 20;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCustomer;
    if (_selected != null) {
      _ctrl.text = _selected!.name;
    }
    _focus.addListener(_onFocusChange);
    _load();
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
    if (_focus.hasFocus && widget.clearOnFocus && !_clearedOnFocus) {
      _clearedOnFocus = true;
      _selected = null;
      _ctrl.clear();
      widget.onSelected?.call(null);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _showRefineHint = false;
    });
    try {
      final service = ref.read(customerServiceProvider);
      final customers = await service.listCustomers();
      if (!mounted) return;
      setState(() {
        _allCustomers = customers;
        _mode = customers.length <= _cap
            ? _FilterMode.client
            : _FilterMode.server;
        _applyBrowseList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[CustomerSearch] load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = VN.customerSearchError;
      });
    }
  }

  void _applyBrowseList() {
    _showRefineHint = false;
    if (_allCustomers.length <= _cap) {
      _listCustomers = List.from(_allCustomers);
    } else {
      final sorted = List<Customer>.from(_allCustomers)
        ..sort((a, b) => b.id.compareTo(a.id));
      _listCustomers = sorted.take(_cap).toList();
    }
  }

  void _onChanged(String value) {
    final query = value.trim();
    if (query.isEmpty) {
      _debounce?.cancel();
      setState(() {
        _applyBrowseList();
        _error = null;
        _showRefineHint = false;
      });
      return;
    }

    if (_mode == _FilterMode.client) {
      setState(() {
        _showRefineHint = false;
        _listCustomers = _allCustomers
            .where((c) => _matchesDiacriticAware(query, c))
            .toList();
        _error = null;
      });
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(customerServiceProvider);
      final results = await service.listCustomers(search: query);
      if (!mounted) return;
      final capped = results.take(_cap).toList();
      setState(() {
        _listCustomers = capped;
        _showRefineHint = results.length > _cap;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[CustomerSearch] search failed: $e');
      if (!mounted) return;
      setState(() {
        _listCustomers = const [];
        _loading = false;
        _error = VN.customerSearchError;
        _showRefineHint = false;
      });
    }
  }

  Future<void> _retry() async {
    final q = _ctrl.text.trim();
    if (_mode == _FilterMode.server && q.isNotEmpty) {
      _search(q);
    } else {
      await _load();
      if (mounted && _error == null && q.isNotEmpty && _mode == _FilterMode.client) {
        _onChanged(_ctrl.text);
      }
    }
  }

  void _select(Customer customer) {
    setState(() {
      _selected = customer;
      _error = null;
    });
    widget.onSelected?.call(customer);
  }

  Widget _errorView() {
    final theme = Theme.of(context);
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
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text(VN.retry),
          ),
        ],
      ),
    );
  }

  Widget _resultsList() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _listCustomers.length,
            itemBuilder: (context, index) {
              final c = _listCustomers[index];
              return ListTile(
                dense: true,
                title: Text(c.name),
                subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                onTap: () => _select(c),
              );
            },
          ),
        ),
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
        if (_showRefineHint)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              VN.customerSearchRefineHint,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.labelText ?? VN.customer,
            hintText: widget.hintText ?? VN.customerSearchHint,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person_search_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorView()
                  : _listCustomers.isEmpty
                      ? Center(
                          child: Text(
                            VN.customerSearchNoMatch,
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
