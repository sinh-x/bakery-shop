import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/address.dart';
import '../../../providers/address/address_autocomplete_provider.dart';
import '../../../shared/labels/address_labels.dart';

/// Reusable delivery-address field with autocomplete suggestions from the
/// address library (DG-385 Phase 4 / FR1/FR2/FR5/AC1/AC2/AC5/AC7).
///
/// Wraps a `TextFormField` (using the caller-supplied [controller] so the
/// wizard/edit state stays the single source of truth) and renders a
/// dropdown overlay of [AddressSuggestion] entries below the field. The
/// provider layer debounces queries for [kAddressAutocompleteDebounce]
/// before hitting `GET /api/addresses/autocomplete`; when [customerId] is
/// supplied, the backend ranks that customer's previously used addresses
/// first (FR5/AC5).
///
/// On selection the widget:
///   - writes the chosen `displayAddress` into [controller] (replacing the
///     partial query the user typed),
///   - invokes [onSelected] with the full [AddressSuggestion] so the caller
///     can auto-bind `googleMapsUrl` to the order (FR2/AC2),
///   - dismisses the dropdown and clears the in-flight debounce.
///
/// The widget is platform-agnostic (NFR2) — no platform-specific plugins.
/// Traceability: FR1, FR2, FR5, FR9, AC1, AC2, AC5, AC7.
class AddressAutocompleteField extends ConsumerStatefulWidget {
  const AddressAutocompleteField({
    super.key,
    required this.controller,
    this.customerId,
    this.onSelected,
    this.labelText,
    this.hintText,
    this.validator,
    this.focusNode,
    this.enabled = true,
  });

  /// The text controller shared with the wizard/edit state. The widget
  /// writes the selected suggestion's `displayAddress` into this controller
  /// and listens to it to drive the debounced autocomplete query.
  final TextEditingController controller;

  /// The selected customer id, used to prioritize that customer's
  /// previously used addresses (FR5/AC5). Null when no customer is
  /// selected.
  final int? customerId;

  /// Called when the user selects a suggestion. The caller auto-binds the
  /// suggestion's `googleMapsUrl` to the order (FR2/AC2).
  final ValueChanged<AddressSuggestion>? onSelected;

  /// Optional label/hint overrides. Default to the shared VN delivery
  /// address label and the address-library hint.
  final String? labelText;
  final String? hintText;
  final String? Function(String?)? validator;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  ConsumerState<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState
    extends ConsumerState<AddressAutocompleteField> {
  late final FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _ownFocusNode = false;
  List<AddressSuggestion> _lastOptions = const [];
  bool _overlayLoading = false;
  bool _overlayError = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownFocusNode = true;
    }
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onControllerChanged);
    // Seed the query notifier with the current customer so an existing
    // prefilled address does not trigger a stale fetch on first focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(addressAutocompleteQueryProvider.notifier)
          .onCustomerChanged(widget.customerId);
    });
  }

  @override
  void didUpdateWidget(covariant AddressAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerId != widget.customerId) {
      // Re-run with the new customer so their addresses move to the top
      // (FR5/AC5) without waiting for the next keystroke.
      ref
          .read(addressAutocompleteQueryProvider.notifier)
          .onCustomerChanged(widget.customerId);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    _hideOverlay();
    if (_ownFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    // Defer to a post-frame callback so we never mutate the Overlay during
    // a focus-driven rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncOverlay();
    });
  }

  void _onControllerChanged() {
    final query = widget.controller.text;
    // Drive the debounced query notifier. The provider layer collapses
    // rapid typing into one network request per burst (FR1/AC1).
    ref
        .read(addressAutocompleteQueryProvider.notifier)
        .onQueryChanged(query, customerId: widget.customerId);
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _refreshOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  /// Reconcile overlay visibility with the current focus + options state.
  /// Always called from a post-frame callback so we never mutate the
  /// Overlay widget during build (the framework forbids that).
  void _syncOverlay() {
    if (!mounted) return;
    final hasContent =
        _lastOptions.isNotEmpty || _overlayLoading || _overlayError;
    if (_focusNode.hasFocus && hasContent) {
      if (_overlayEntry == null) {
        _showOverlay();
      } else {
        _refreshOverlay();
      }
    } else if (_overlayEntry != null) {
      _hideOverlay();
    }
  }

  void _selectSuggestion(AddressSuggestion suggestion) {
    widget.controller.text = suggestion.displayAddress;
    widget.controller.selection = TextSelection.collapsed(
      offset: suggestion.displayAddress.length,
    );
    widget.onSelected?.call(suggestion);
    ref.read(addressAutocompleteQueryProvider.notifier).clear();
    _hideOverlay();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the debounced request the query notifier published, then read
    // the fetch provider with it. This keeps the rebuild surface tight:
    // only the field + its overlay rebuild on new suggestions.
    final request = ref.watch(addressAutocompleteQueryProvider);
    final asyncOptions = ref.watch(addressAutocompleteProvider(request));

    if (request.isValid) {
      asyncOptions.when(
        data: (data) {
          _lastOptions = data;
          _overlayLoading = false;
          _overlayError = false;
        },
        loading: () {
          _overlayLoading = true;
          _overlayError = false;
        },
        error: (_, _) {
          _overlayLoading = false;
          _overlayError = true;
        },
      );
    } else {
      _lastOptions = const [];
      _overlayLoading = false;
      _overlayError = false;
    }

    // Sync overlay visibility with the current options/focus state. The
    // overlay mutates the Overlay widget, so all insert/remove/markNeeds
    // calls are deferred to a post-frame callback — calling them during
    // build throws ("setState() or markNeedsBuild() called during build").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncOverlay();
    });

    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: widget.labelText ?? VN.deliveryAddress,
          hintText: widget.hintText ?? AddressLabels.autocompleteHint,
          border: const OutlineInputBorder(),
        ),
        validator: widget.validator,
        onChanged: (value) {
          // The controller listener already drives the debounce; this hook
          // exists so subclasses/tests can observe raw input if needed.
        },
      ),
    );
  }

  Widget _buildOverlay(BuildContext ctx) {
    final mediaQuery = MediaQuery.of(ctx);
    return Positioned(
      width: _layerLink.leaderSize?.width ?? 250,
      child: CompositedTransformFollower(
        link: _layerLink,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 4),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.3,
              minWidth: 200,
            ),
            child: _buildOverlayBody(_lastOptions, _overlayLoading, _overlayError),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayBody(
    List<AddressSuggestion> options,
    bool loading,
    bool hasError,
  ) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(AddressLabels.autocompleteLoading),
          ],
        ),
      );
    }
    if (hasError) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          AddressLabels.autocompleteError,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(AddressLabels.autocompleteNoResults),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: options.length,
      itemBuilder: (ctx, i) {
        final suggestion = options[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.location_on_outlined, size: 18),
          title: Text(suggestion.displayAddress),
          subtitle: suggestion.isCustomerAddress
              ? const Text(
                  AddressLabels.customerAddressBadge,
                  style: TextStyle(fontSize: 11),
                )
              : null,
          trailing: suggestion.googleMapsUrl != null
              ? const Icon(Icons.map_outlined, size: 16)
              : null,
          onTap: () => _selectSuggestion(suggestion),
        );
      },
    );
  }
}