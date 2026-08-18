import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_crud_providers.dart';
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
  bool _saving = false;

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
    setState(() => _saving = true);
    try {
      final value = clear ? null : _urlCtrl.text.trim();
      await ref
          .read(orderDetailProvider(widget.orderRef).notifier)
          .save(googleMapsUrl: value);
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            onChanged: (_) => setState(() {}),
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
                  onPressed: _saving ? null : () => _save(clear: true),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text(OrdersLabels.googleMapsModalClear),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () => _save(clear: _urlCtrl.text.trim().isEmpty),
            icon: _saving
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