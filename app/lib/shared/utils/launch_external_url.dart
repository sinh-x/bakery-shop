import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bakery_app/shared/labels/orders.dart';

/// Launches [url] in the external application via `url_launcher`.
///
/// Checks `canLaunchUrl` before opening and shows a snackbar on failure.
/// Empty or whitespace-only URLs are ignored silently. The caller is
/// responsible for passing a still-mounted [context] (the function guards
/// with `context.mounted` before showing any snackbar).
///
/// DG-303 review-auto CQ-1: consolidates the duplicated `_launchMap` /
/// `_launchMapUrl` implementations that previously lived inline in
/// `order_detail_screen.dart`, `order_edit_screen.dart`,
/// `delivery_order_card.dart`, and `stage3_delivery_options_screen.dart`.
Future<void> launchExternalUrl(BuildContext context, String? url) async {
  final trimmed = url?.trim() ?? '';
  if (trimmed.isEmpty) return;
  final uri = Uri.parse(trimmed);
  if (!await canLaunchUrl(uri)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(OrdersLabels.cannotOpenMap)),
    );
    return;
  }
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(OrdersLabels.cannotOpenMap)),
    );
  }
}