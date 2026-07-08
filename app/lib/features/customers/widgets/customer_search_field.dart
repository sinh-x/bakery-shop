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
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  Timer? _debounce;

  List<Customer> _results = const [];
  bool _loading = false;
  bool _showing = false;
  Customer? _selected;
  bool _clearedOnFocus = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCustomer;
    if (_selected != null) {
      _ctrl.text = _selected!.name;
    }
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideOverlay();
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
    if (_focus.hasFocus && _ctrl.text.isNotEmpty && !_showing) {
      _showResults();
    } else if (!_focus.hasFocus && _showing) {
      Future.delayed(const Duration(milliseconds: 150), _hideOverlay);
    }
  }

  void _onChanged(String value) {
    if (value.trim().isEmpty) {
      _debounce?.cancel();
      _hideOverlay();
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(customerServiceProvider);
      final results = await service.listCustomers(search: query);
      if (!mounted) return;
      final filtered = results
          .where((c) => _matchesDiacriticAware(query, c))
          .toList();
      setState(() {
        _results = filtered;
        _loading = false;
      });
      _showResults();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
        _error = VN.customerSearchError;
      });
    }
  }

  void _retry() {
    _search();
  }

  void _showResults() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: (_) => _buildOverlayBox());
    Overlay.of(context).insert(_overlay!);
    _showing = true;
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
    _showing = false;
  }

  void _select(Customer customer) {
    setState(() {
      _selected = customer;
      _ctrl.clear();
      _error = null;
    });
    _hideOverlay();
    widget.onSelected?.call(customer);
  }

  Widget _buildOverlayBox() {
    final theme = Theme.of(context);
    return Positioned(
      width: _layerLink.leaderSize?.width,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 56),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      VN.customerSearchNoMatch,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final c in _results)
                        ListTile(
                          dense: true,
                          title: Text(c.name),
                          subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                          onTap: () => _select(c),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(
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
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: Text(
                      VN.retry,
                      style: theme.textTheme.bodySmall,
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          if (_selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    VN.customerSearchLinked.replaceAll(
                      '{name}',
                      _selected!.name,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
