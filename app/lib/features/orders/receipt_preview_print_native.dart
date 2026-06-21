import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/services/printer_service.dart';
import '../../providers/paper_mode_provider.dart';
import '../../shared/widgets/printer_picker_dialog.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Native (Android/iOS) Bluetooth print via TSPL.
Future<void> printNative(BuildContext context, Uint8List imageBytes, dynamic ref) async {
  final widgetRef = ref as WidgetRef;
  final printerService = widgetRef.read(printerServiceProvider);
  await printerService.init();

  // Try auto-reconnect to last printer
  if (printerService.lastPrinterMac != null) {
    try {
      await printerService.connect(printerService.lastPrinterMac!);
      final paperMode = widgetRef.read(paperModeProvider).asData?.value ?? 'label';
      final trailMm = widgetRef.read(trailMmProvider).asData?.value ?? 20;
      await printerService.printImage(imageBytes,
          paperMode: paperMode, trailMm: trailMm);
      if (context.mounted) {
        showTopSnackBar(context, VN.printSuccess);
      }
      return;
    } catch (_) {
      // Fall through to picker
    }
  }

  if (!context.mounted) return;
  final result = await showPrinterPickerDialog(
    context: context,
    imageBytes: imageBytes,
    printerService: printerService,
  );

  if (!context.mounted) return;
  if (result == PrinterPickerResult.success) {
    showTopSnackBar(context, VN.printSuccess);
  }
}

/// Tries to print and returns the result without showing snackbar.
/// Used by Flow B for auto-confirm logic.
Future<PrinterPickerResult> tryPrintNative(
  BuildContext context,
  Uint8List imageBytes,
  WidgetRef widgetRef,
) async {
  final printerService = widgetRef.read(printerServiceProvider);
  await printerService.init();

  // Try auto-reconnect to last printer
  if (printerService.lastPrinterMac != null) {
    try {
      await printerService.connect(printerService.lastPrinterMac!);
      final paperMode = widgetRef.read(paperModeProvider).asData?.value ?? 'label';
      final trailMm = widgetRef.read(trailMmProvider).asData?.value ?? 20;
      await printerService.printImage(imageBytes,
          paperMode: paperMode, trailMm: trailMm);
      return PrinterPickerResult.success;
    } catch (_) {
      // Fall through to picker
    }
  }

  if (!context.mounted) return PrinterPickerResult.cancelled;

  final result = await showPrinterPickerDialog(
    context: context,
    imageBytes: imageBytes,
    printerService: printerService,
  );

  return result;
}

/// No-op on native — web only.
void printWeb(Uint8List imageBytes) {}

/// Save image to app documents directory.
Future<void> saveToFile(Uint8List imageBytes, String fileName) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(imageBytes);
}
