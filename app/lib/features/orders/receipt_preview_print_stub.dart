import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../shared/widgets/printer_picker_dialog.dart';

/// Stub — should never be called (overridden by native or web impl).
Future<void> printNative(BuildContext context, Uint8List imageBytes, dynamic ref) async {}

Future<PrinterPickerResult> tryPrintNative(
  BuildContext context,
  Uint8List imageBytes,
  dynamic ref,
) async {
  return PrinterPickerResult.cancelled;
}

void printWeb(Uint8List imageBytes) {}

Future<void> saveToFile(Uint8List imageBytes, String fileName) async {}
