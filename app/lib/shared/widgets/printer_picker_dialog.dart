import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../data/services/printer_service.dart';
import '../../providers/paper_mode_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Result of the printer picker dialog.
enum PrinterPickerResult {
  cancelled,
  success,
  failed,
}

/// Shows the printer picker bottom sheet and handles the print flow.
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
  _PickerState _state = _PickerState.loading;
  List<DiscoveredPrinter> _devices = [];
  String? _errorMessage;
  String? _connectingToName;

  @override
  void initState() {
    super.initState();
    _loadBondedDevices();
  }

  Future<void> _loadBondedDevices() async {
    setState(() {
      _state = _PickerState.loading;
      _errorMessage = null;
    });

    try {
      // Check Bluetooth permission (Android 12+)
      final hasPermission =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!hasPermission) {
        setState(() {
          _state = _PickerState.error;
          _errorMessage =
              'Cần cấp quyền Bluetooth. Vào Cài đặt > Ứng dụng > Đoàn Gia > Quyền > Bluetooth';
        });
        return;
      }

      final btEnabled = await widget.printerService.isBluetoothEnabled();
      if (!btEnabled) {
        setState(() {
          _state = _PickerState.error;
          _errorMessage = printerErrorMessage(PrinterError.bluetoothDisabled);
        });
        return;
      }

      final devices = await widget.printerService.getBondedDevices();
      if (!mounted) return;

      setState(() {
        _devices = devices;
        _state =
            devices.isEmpty ? _PickerState.noDevices : _PickerState.deviceList;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _PickerState.error;
        _errorMessage = printerErrorMessage(PrinterError.bluetoothScanFailed);
      });
    }
  }

  Future<void> _onDeviceSelected(DiscoveredPrinter device, {bool testOnly = false}) async {
    setState(() {
      _state = _PickerState.connecting;
      _connectingToName = device.name;
    });

    try {
      await widget.printerService.connect(device.address);

      setState(() => _state = _PickerState.printing);

      if (testOnly) {
        // Send plain text test to verify TSPL protocol
        await widget.printerService.printTest();
      } else {
        final settings = ref.read(paperSettingsProvider).asData?.value ?? const PaperSettings();
        final paperMode = settings.paperMode;
        final trailMm = settings.trailMm;
        await widget.printerService.printImage(widget.imageBytes,
            paperMode: paperMode, trailMm: trailMm);
      }

      if (mounted) {
        Navigator.of(context).pop(PrinterPickerResult.success);
      }
    } on PrinterException catch (e) {
      if (mounted) {
        setState(() {
          _state = _PickerState.error;
          _errorMessage =
              '${printerErrorMessage(e.error)}\n\nKiểm tra máy in đã bật và không kết nối với ứng dụng khác';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _PickerState.error;
          _errorMessage =
              '${VN.printerConnectionFailed}\n\nLỗi: $e';
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
            _buildActions(),
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
    switch (_state) {
      case _PickerState.loading:
        return _buildLoadingContent();
      case _PickerState.deviceList:
        return _buildDeviceList();
      case _PickerState.noDevices:
        return _buildNoDevicesContent();
      case _PickerState.connecting:
        return _buildConnectingContent();
      case _PickerState.printing:
        return _buildPrintingContent();
      case _PickerState.error:
        return _buildErrorContent();
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

  Widget _buildDeviceList() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
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
            VN.noDevicesFound,
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

  Widget _buildPrintingContent() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 16),
          Text(
            VN.printing,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
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

  Widget _buildActions() {
    if (_state == _PickerState.loading ||
        _state == _PickerState.connecting ||
        _state == _PickerState.printing) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_state == _PickerState.error ||
              _state == _PickerState.noDevices) ...[
            FilledButton.icon(
              onPressed: _loadBondedDevices,
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

enum _PickerState {
  loading,
  deviceList,
  noDevices,
  connecting,
  printing,
  error,
}
