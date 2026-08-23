import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../data/services/printer_service.dart';
import '../../providers/printer_picker_notifier.dart';
import '../../providers/printer_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Result of the printer picker dialog.
enum PrinterPickerResult { cancelled, success, failed }

/// Shows the printer picker bottom sheet and handles the print flow.
Future<PrinterPickerResult> showPrinterPickerDialog({
  required BuildContext context,
  required Uint8List imageBytes,
  required PrinterService printerService,
}) async {
  final pickerContext = PrinterPickerDialogContext();
  final result = await showModalBottomSheet<PrinterPickerResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => PrinterPickerBottomSheet(
      imageBytes: imageBytes,
      printerService: printerService,
      pickerContext: pickerContext,
    ),
  );
  return result ?? PrinterPickerResult.cancelled;
}

/// Bottom sheet widget for picking a Bluetooth printer and printing.
class PrinterPickerBottomSheet extends ConsumerStatefulWidget {
  const PrinterPickerBottomSheet({
    super.key,
    required this.imageBytes,
    required this.printerService,
    this.pickerContext,
  });

  final Uint8List imageBytes;
  final PrinterService printerService;
  final PrinterPickerDialogContext? pickerContext;

  @override
  ConsumerState<PrinterPickerBottomSheet> createState() =>
      _PrinterPickerBottomSheetState();
}

class _PrinterPickerBottomSheetState
    extends ConsumerState<PrinterPickerBottomSheet> {
  late final _pickerContext =
      widget.pickerContext ?? PrinterPickerDialogContext();

  @override
  void initState() {
    super.initState();
    // Deferred to a microtask so we don't mutate providers during the
    // widget-tree build phase (DG-404 Phase 4.7).
    Future.microtask(_loadBondedDevices);
  }

  Future<void> _loadBondedDevices() async {
    final notifier = ref.read(printerPickerProvider(_pickerContext).notifier);
    final printerService = widget.printerService;
    notifier.startLoading();

    try {
      // Check Bluetooth permission (Android 12+)
      final hasPermission =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!mounted) return;
      if (!hasPermission) {
        notifier.setError(
          'Cần cấp quyền Bluetooth. Vào Cài đặt > Ứng dụng > Đoàn Gia > Quyền > Bluetooth',
        );
        return;
      }

      final btEnabled = await printerService.isBluetoothEnabled();
      if (!mounted) return;
      if (!btEnabled) {
        notifier.setError(printerErrorMessage(PrinterError.bluetoothDisabled));
        return;
      }

      final devices = await printerService.getBondedDevices();
      if (!mounted) return;

      notifier.setDevices(devices);
    } catch (e) {
      if (!mounted) return;
      notifier.setError(printerErrorMessage(PrinterError.bluetoothScanFailed));
    }
  }

  Future<void> _onDeviceSelected(
    DiscoveredPrinter device, {
    bool testOnly = false,
  }) async {
    final notifier = ref.read(printerPickerProvider(_pickerContext).notifier);
    final printerService = widget.printerService;
    final imageBytes = widget.imageBytes;
    final printerNotifier = ref.read(printerProvider.notifier);
    notifier.startConnecting(device.name);

    try {
      await printerService.connect(device.address);
      if (!mounted) return;

      notifier.setPrinting();

      if (testOnly) {
        await printerService.printTest();
        if (!mounted) return;
      } else {
        final success = await printerNotifier.printImage(imageBytes);
        if (!mounted) return;

        if (!success) {
          final printerStatus = ref.read(printerProvider).asData?.value;
          notifier.setError(
            printerStatus?.errorMessage ?? SharedLabels.printerConnectionFailed,
          );
          return;
        }
      }

      if (mounted) {
        Navigator.of(context).pop(PrinterPickerResult.success);
      }
    } on PrinterException catch (e) {
      if (!mounted) return;
      notifier.setError(
        '${printerErrorMessage(e.error)}\n\nKiểm tra máy in đã bật và không kết nối với ứng dụng khác',
      );
    } catch (e) {
      if (!mounted) return;
      notifier.setError('${SharedLabels.printerConnectionFailed}\n\nLỗi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickerState = ref.watch(printerPickerProvider(_pickerContext));
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            _buildHeader(),
            const Divider(height: 1),
            _buildContent(pickerState),
            _buildActions(pickerState),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: 32,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.bluetooth, size: 24),
          const SizedBox(width: 8),
          Text(
            SharedLabels.selectPrinter,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          IconButton(
            onPressed: () =>
                Navigator.of(context).pop(PrinterPickerResult.cancelled),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(PrinterPickerDialogState pickerState) {
    switch (pickerState.phase) {
      case PrinterPickerPhase.loading:
        return _buildLoadingContent();
      case PrinterPickerPhase.deviceList:
        return _buildDeviceList(pickerState);
      case PrinterPickerPhase.noDevices:
        return _buildNoDevicesContent();
      case PrinterPickerPhase.connecting:
        return _buildConnectingContent(pickerState);
      case PrinterPickerPhase.printing:
        return _buildPrintingContent();
      case PrinterPickerPhase.error:
        return _buildErrorContent(pickerState);
    }
  }

  Widget _buildLoadingContent() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          CircularProgressIndicator(strokeWidth: 2),
          SizedBox(height: 16),
          Text('Đang tải danh sách thiết bị...'),
        ],
      ),
    );
  }

  Widget _buildDeviceList(PrinterPickerDialogState pickerState) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: pickerState.devices.length,
        itemBuilder: (context, index) {
          final device = pickerState.devices[index];
          return ListTile(
            leading: const Icon(Icons.bluetooth),
            title: Text(device.name),
            subtitle: Text(device.address),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _onDeviceSelected(device, testOnly: true),
                  child: const Text('Test'),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _onDeviceSelected(device),
          );
        },
      ),
    );
  }

  Widget _buildNoDevicesContent() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.bluetooth_disabled,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            SharedLabels.noDevicesFound,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Vui lòng ghép nối máy in trong Cài đặt Bluetooth của điện thoại trước',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingContent(PrinterPickerDialogState pickerState) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 16),
          Text(
            SharedLabels.connectingTo,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (pickerState.connectingToName != null) ...[
            const SizedBox(height: 8),
            Text(
              pickerState.connectingToName!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrintingContent() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 16),
          Text(
            SharedLabels.printing,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorContent(PrinterPickerDialogState pickerState) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            pickerState.errorMessage ?? SharedLabels.printerConnectionFailed,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActions(PrinterPickerDialogState pickerState) {
    if (pickerState.phase == PrinterPickerPhase.loading ||
        pickerState.phase == PrinterPickerPhase.connecting ||
        pickerState.phase == PrinterPickerPhase.printing) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (pickerState.phase == PrinterPickerPhase.error ||
              pickerState.phase == PrinterPickerPhase.noDevices) ...[
            FilledButton.icon(
              onPressed: _loadBondedDevices,
              icon: const Icon(Icons.refresh),
              label: const Text(SharedLabels.tapToRetry),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(PrinterPickerResult.cancelled),
            child: const Text(SharedLabels.cancel),
          ),
        ],
      ),
    );
  }
}
