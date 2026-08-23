import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_crud_providers.dart';
import '../providers/google_maps_modal_notifier.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/utils/api_error.dart';
import '../../../shared/utils/launch_external_url.dart';
import 'section_header.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Google Maps URL viewer/editor modal (DG-306 Phase 3 / FR6 / AC6).
///
/// Opened from the order detail screen's context menu. Displays the current
/// `googleMapsUrl` value (or an empty-state hint when none is set), lets the
/// user open the URL in the external maps app, and save edits or clear the
/// value via `OrderDetailNotifier.save`. GPS coordinate fields (lat/lon)
/// remain in the create/edit forms — only the URL lives here.
class GoogleMapsModal extends ConsumerStatefulWidget {
  const GoogleMapsModal({
    super.key,
    required this.orderRef,
    required this.initialUrl,
  });

  final String orderRef;
  final String? initialUrl;

  @override
  ConsumerState<GoogleMapsModal> createState() => _GoogleMapsModalState();
}

class _GoogleMapsModalState extends ConsumerState<GoogleMapsModal> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final savingNotifier = container.read(googleMapsModalProvider.notifier);
    final orderDetail = container.read(
      orderDetailProvider(widget.orderRef).notifier,
    );
    savingNotifier.setSaving(true);
    try {
      final value = clear ? null : _urlCtrl.text.trim();
      await orderDetail.save(googleMapsUrl: value);
      if (mounted) {
        showTopSnackBar(
          context,
          clear ? OrdersLabels.googleMapsModalCleared : OrdersLabels.googleMapsModalSaved,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: ${normalizeApiError(e).message}');
      }
    } finally {
      savingNotifier.setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saving = ref.watch(googleMapsModalProvider);
    final hasUrl = _urlCtrl.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(OrdersLabels.googleMapsModalTitle),
          const SizedBox(height: 4),
          Text(
            OrdersLabels.googleMapsModalHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: OrdersLabels.googleMapsUrlLabel,
              hintText: OrdersLabels.googleMapsModalEmpty,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            keyboardType: TextInputType.url,
            maxLines: 3,
            // onChanged no longer needs setState — the hasUrl derivation
            // re-runs on every rebuild triggered by the controller's
            // internal notification through the FormField's rebuild scope.
            // The `setState(() {})` previously here was a pure rebuild
            // signal for `hasUrl`; the TextFormField already rebuilds its
            // own subtree on text changes, and the outer Column is
            // rebuilt via the `saving` watch on every notifier change.
            // To preserve the hasUrl-driven button visibility, trigger a
            // rebuild via the saving notifier (a no-op bump).
            onChanged: (_) =>
                ref.read(googleMapsModalProvider.notifier).setSaving(saving),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: hasUrl
                    ? () => launchExternalUrl(context, _urlCtrl.text.trim())
                    : null,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text(OrdersLabels.googleMapsModalOpenMap),
              ),
              if (hasUrl)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: saving ? null : () => _save(clear: true),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text(OrdersLabels.googleMapsModalClear),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: saving
                ? null
                : () => _save(clear: _urlCtrl.text.trim().isEmpty),
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: const Text(OrdersLabels.googleMapsModalSave),
          ),
        ],
      ),
    );
  }
}
