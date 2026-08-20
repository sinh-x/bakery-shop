import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
Future<Object?> showTransferSourceDialog(BuildContext context) {
  return showDialog<Object>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text(OrdersLabels.transferProofTitle),
      content: const Text(OrdersLabels.transferProofPrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, 'skip'),
          child: const Text(OrdersLabels.skip),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, ImageSource.camera),
          child: const Text(ProductsLabels.takePhoto),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogCtx, ImageSource.gallery),
          child: const Text(OrdersLabels.photoLibrary),
        ),
      ],
    ),
  );
}

Future<void> showClearCartDialog({
  required BuildContext context,
  required VoidCallback onConfirm,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text(OrdersLabels.clearCartTitle),
      content: const Text(OrdersLabels.clearCartPrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton(
          onPressed: () {
            onConfirm();
            Navigator.pop(dialogCtx);
          },
          child: const Text(OrdersLabels.clear),
        ),
      ],
    ),
  );
}
