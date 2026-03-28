import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/printer_service.dart';
import 'vietnamese_labels.dart';

/// Result of the printer picker dialog.
enum PrinterPickerResult {
  /// User cancelled the picker.
  cancelled,

  /// Printing completed successfully.
  success,

  /// Printing failed.
  failed,
}

/// Shows the printer picker bottom sheet and handles the print flow.
///
/// Returns [PrinterPickerResult.success] if printing succeeded,
/// [PrinterPickerResult.failed] if printing failed,
/// [PrinterPickerResult.cancelled] if user cancelled.
Future<PrinterPickerResult> showPrinterPickerDialog({
  required BuildContext context,
  required Uint8List imageBytes,
  required PrinterService printerService,
}) async {
  final result = await showModalBottomSheet<PrinterPickerResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => PrinterPickerBottomSheet(
      imageBytes: imageBytes,
      printerService: printerService,
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
  });

  final Uint8List imageBytes;
  final PrinterService printerService;

  @override
  ConsumerState<PrinterPickerBottomSheet> createState() =>
      _PrinterPickerBottomSheetState();
}

class _PrinterPickerBottomSheetState
    extends ConsumerState<PrinterPickerBottomSheet> {
  /// Current scan state.
  _ScanState _scanState = _ScanState.scanning;

  /// List of discovered printers.
  List<Printer> _discoveredPrinters = [];

  /// Error message if scan or connection failed.
  String? _errorMessage;

  /// The printer being connected to (for display).
  String? _connectingToName;

  StreamSubscription<List<Printer>>? _devicesSubscription;
  Timer? _scanTimeout;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _scanTimeout?.cancel();
    widget.printerService.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanState = _ScanState.scanning;
      _errorMessage = null;
      _discoveredPrinters = [];
    });

    // Listen to device discoveries
    _devicesSubscription?.cancel();
    _devicesSubscription = widget.printerService.devicesStream.listen(
      (printers) {
        if (mounted) {
          setState(() {
            _discoveredPrinters = printers;
          });
        }
      },
    );

    // Start scanning
    await widget.printerService.startScan();

    // Timeout after 15 seconds
    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        _onScanComplete();
      }
    });
  }

  void _onScanComplete() {
    widget.printerService.stopScan();
    _devicesSubscription?.cancel();

    if (mounted) {
      setState(() {
        if (_discoveredPrinters.isEmpty) {
          _scanState = _ScanState.noDevices;
          _errorMessage = VN.noPrinterFound;
        } else {
          _scanState = _ScanState.foundDevices;
        }
      });
    }
  }

  Future<void> _onDeviceSelected(Printer printer) async {
    setState(() {
      _scanState = _ScanState.connecting;
      _connectingToName = printer.name ?? printer.address;
    });

    try {
      await widget.printerService.connectPrinter(printer);
      await widget.printerService.printImage(widget.imageBytes);

      if (mounted) {
        Navigator.of(context).pop(PrinterPickerResult.success);
      }
    } on PrinterException catch (e) {
      if (mounted) {
        setState(() {
          _scanState = _ScanState.error;
          _errorMessage = printerErrorMessage(e.error);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanState = _ScanState.error;
          _errorMessage = VN.printerConnectionFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _buildContent(),
            _buildRetryButton(),
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
          const Icon(Icons.bluetooth_searching, size: 24),
          const SizedBox(width: 8),
          Text(
            VN.selectPrinter,
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

  Widget _buildContent() {
    switch (_scanState) {
      case _ScanState.scanning:
        return _buildScanningContent();
      case _ScanState.foundDevices:
        return _buildDeviceList();
      case _ScanState.noDevices:
        return _buildNoDevicesContent();
      case _ScanState.connecting:
        return _buildConnectingContent();
      case _ScanState.error:
        return _buildErrorContent();
    }
  }

  Widget _buildScanningContent() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 16),
          Text(
            VN.scanning,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          if (_discoveredPrinters.isNotEmpty) ...[
            Text(
              '${_discoveredPrinters.length} thiết bị tìm thấy...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _discoveredPrinters.length,
        itemBuilder: (context, index) {
          final printer = _discoveredPrinters[index];
          return ListTile(
            leading: const Icon(Icons.bluetooth),
            title: Text(printer.name ?? 'Unknown'),
            subtitle: Text(printer.address ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _onDeviceSelected(printer),
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
            VN.noDevicesFound,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            VN.noPrinterFound,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingContent() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 16),
          Text(
            VN.connectingTo,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (_connectingToName != null) ...[
            const SizedBox(height: 8),
            Text(
              _connectingToName!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorContent() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? VN.printerConnectionFailed,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRetryButton() {
    if (_scanState == _ScanState.scanning ||
        _scanState == _ScanState.connecting) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_scanState == _ScanState.error ||
              _scanState == _ScanState.noDevices) ...[
            FilledButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.refresh),
              label: const Text(VN.tapToRetry),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(PrinterPickerResult.cancelled),
            child: const Text(VN.cancel),
          ),
        ],
      ),
    );
  }
}

enum _ScanState {
  scanning,
  foundDevices,
  noDevices,
  connecting,
  error,
}