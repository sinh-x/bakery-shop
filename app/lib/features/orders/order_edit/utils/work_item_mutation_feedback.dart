import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:bakery_app/shared/utils/api_error.dart';
import 'package:flutter/material.dart';

void showWorkItemMutationFailure(
  BuildContext context, {
  required String action,
  required Object error,
}) {
  showTopSnackBar(
    context,
    buildApiActionFailureMessage(action: action, error: error),
  );
}

void showWorkItemRefreshFailure(
  BuildContext context, {
  required String action,
  required Object error,
  required VoidCallback onRetry,
}) {
  showTopSnackBar(
    context,
    buildApiActionFailureMessage(
      action: action,
      error: error,
      nextStep: OrdersLabels.orderDetailRefreshRecovery,
    ),
    actionLabel: SharedLabels.retry,
    onAction: onRetry,
  );
}
