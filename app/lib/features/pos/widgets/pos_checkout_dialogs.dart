import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/labels/shared.dart';

Future<Object?> showTransferSourceDialog(BuildContext context) {
  return showDialog<Object>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text(VN.transferProofTitle),
      content: const Text(VN.transferProofPrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, 'skip'),
          child: const Text(VN.skip),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, ImageSource.camera),
          child: const Text('📷 Camera'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogCtx, ImageSource.gallery),
          child: const Text(VN.photoLibrary),
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
      title: const Text(VN.clearCartTitle),
      content: const Text(VN.clearCartPrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text(VN.cancel),
        ),
        FilledButton(
          onPressed: () {
            onConfirm();
            Navigator.pop(dialogCtx);
          },
          child: const Text(VN.clear),
        ),
      ],
    ),
  );
}
