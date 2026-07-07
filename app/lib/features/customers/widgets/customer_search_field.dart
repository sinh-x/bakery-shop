import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/customer_service.dart';
import '../../../data/models/customer.dart';
import 'package:bakery_app/shared/labels/customers.dart';

/// Standalone customer search field for reuse in POS checkout (FR10) and
/// order creation (FR11). Search is on-demand and debounced so the walk-in
/// flow is unaffected when the field is left empty (NFR2).
///
/// Exposes the selected customer via [onSelected]; pass `null` to clear. The
/// field is optional — leaving it untouched results in `customerId == null`,
/// preserving the existing "Khách lẻ" walk-in behavior.
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

  /// Called whenever the selection changes. Receives `null` when the user
  /// clears the selection.
  final ValueChanged<Customer?>? onSelected;

  /// Pre-selected customer (used when editing an existing order).
  final Customer? initialCustomer;

  /// Optional external controller. When provided, the field uses this
  /// controller instead of an internal one so the parent can read the typed
  /// text (e.g. for the walk-in name in order create). When null, an internal
  /// controller is created and disposed with the widget.
  final TextEditingController? controller;

  /// Optional label override; defaults to the shared VN label.
  final String? labelText;

  /// Optional hint override; defaults to the shared VN search hint.
  final String? hintText;

  /// When true, on first focus, clears the pre-filled text and selected
  /// customer so the staff can search freely (POS auto-clear behavior).
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
    // Only dispose the internal controller; external controllers are owned by
    // the parent widget.
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
      // Delay to allow tap on a suggestion to register.
      Future.delayed(const Duration(milliseconds: 150), _hideOverlay);
    }
  }

  void _onChanged(String value) {
    // While typing, clear any previous selection — the displayed text no
    // longer matches a concrete customer record.
    if (_selected != null && value != _selected!.name) {
      _selected = null;
      widget.onSelected?.call(null);
    }
    if (value.trim().isEmpty) {
      _debounce?.cancel();
      _hideOverlay();
      setState(() {
        _results = const [];
        _loading = false;
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
    setState(() => _loading = true);
    try {
      final service = ref.read(customerServiceProvider);
      final results = await service.listCustomers(search: query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      _showResults();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
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
      _ctrl.text = customer.name;
      _ctrl.selection = TextSelection.collapsed(offset: customer.name.length);
    });
    _hideOverlay();
    widget.onSelected?.call(customer);
  }

  void _clear() {
    setState(() {
      _selected = null;
      _ctrl.clear();
    });
    _hideOverlay();
    widget.onSelected?.call(null);
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
              suffixIcon: _selected != null
                  ? IconButton(
                      tooltip: VN.customerSearchClear,
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _clear,
                    )
                  : null,
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