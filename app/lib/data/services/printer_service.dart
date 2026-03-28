import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// Error types for printer operations.
enum PrinterError {
  bluetoothNotAvailable,
  bluetoothDisabled,
  locationPermissionDenied,
  bluetoothScanFailed,
  printerNotFound,
  connectionFailed,
  connectionLost,
  printFailed,
  outOfPaper,
  unknown,
}

/// Vietnamese error messages for [PrinterError].
String printerErrorMessage(PrinterError error) {
  switch (error) {
    case PrinterError.bluetoothNotAvailable:
      return 'Bluetooth không khả dụng trên thiết bị này';
    case PrinterError.bluetoothDisabled:
      return 'Bluetooth đang tắt. Vui lòng bật Bluetooth';
    case PrinterError.locationPermissionDenied:
      return 'Cần quyền vị trí để quét thiết bị Bluetooth';
    case PrinterError.bluetoothScanFailed:
      return 'Không thể quét thiết bị Bluetooth';
    case PrinterError.printerNotFound:
      return 'Không tìm thấy máy in. Vui lòng kiểm tra máy in đã bật';
    case PrinterError.connectionFailed:
      return 'Không thể kết nối máy in';
    case PrinterError.connectionLost:
      return 'Mất kết nối máy in';
    case PrinterError.printFailed:
      return 'Không thể in. Vui lòng thử lại';
    case PrinterError.outOfPaper:
      return 'Máy in hết giấy';
    case PrinterError.unknown:
      return 'Đã xảy ra lỗi không xác định';
  }
}

/// Represents a discovered Bluetooth printer device.
class DiscoveredPrinter {
  final String name;
  final String address;
  final bool isConnected;

  DiscoveredPrinter({
    required this.name,
    required this.address,
    this.isConnected = false,
  });
}

/// Manages Bluetooth thermal printer discovery, connection, and printing.
///
/// This service is independent of the UI framework and can be tested
/// standalone. It handles:
/// - Scanning for nearby Bluetooth printers
/// - Connecting to and disconnecting from a printer
/// - Sending receipt images to the printer
/// - Auto-reconnect to the last-used printer via SharedPreferences
class PrinterService {
  static const String _lastPrinterMacKey = 'last_printer_mac';

  SharedPreferences? _prefs;
  Printer? _connectedPrinter;
  String? _lastMac;
  StreamSubscription<List<Printer>>? _devicesSubscription;

  /// Initializes the service. Must be called before any other methods.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _lastMac = _prefs?.getString(_lastPrinterMacKey);
  }

  /// Returns the last-used printer MAC address, or null if none saved.
  String? get lastPrinterMac => _lastMac;

  /// Returns the currently connected printer, or null if not connected.
  Printer? get connectedPrinter => _connectedPrinter;

  /// Returns true if a printer is currently connected.
  bool get isConnected => _connectedPrinter != null;

  /// Checks if Bluetooth is enabled on the device.
  Future<bool> isBluetoothEnabled() async {
    return FlutterThermalPrinter.instance.isBleTurnedOn();
  }

  /// Starts scanning for Bluetooth printers.
  ///
  /// Scanned devices are emitted via [devicesStream].
  /// Call [stopScan] to stop scanning.
  Future<void> startScan() async {
    _devicesSubscription?.cancel();
    _devicesSubscription = FlutterThermalPrinter.instance.devicesStream.listen(
      (_) {}, // We just need to ensure the stream is active
    );
    await FlutterThermalPrinter.instance.getPrinters(
      connectionTypes: const [ConnectionType.BLE],
      androidUsesFineLocation: true,
    );
  }

  /// Stops scanning for printers.
  Future<void> stopScan() async {
    await FlutterThermalPrinter.instance.stopScan();
    _devicesSubscription?.cancel();
    _devicesSubscription = null;
  }

  /// Stream of discovered printers.
  ///
  /// Listen to this stream to receive updates when printers are found.
  Stream<List<Printer>> get devicesStream =>
      FlutterThermalPrinter.instance.devicesStream;

  /// Connects to a printer by MAC address.
  ///
  /// After connecting, saves the MAC to SharedPreferences for auto-reconnect.
  /// Returns the connected [Printer] object.
  Future<Printer> connect(String macAddress) async {
    // Find the printer in the discovered devices
    final printers = await _getPrintersWithTimeout();
    Printer? printer = printers.firstWhere(
      (p) => p.address == macAddress,
      orElse: () => throw PrinterException(PrinterError.printerNotFound),
    );

    final connected = await FlutterThermalPrinter.instance.connect(printer);
    if (!connected) {
      throw PrinterException(PrinterError.connectionFailed);
    }

    printer = printer.copyWith(isConnected: true);
    _connectedPrinter = printer;
    _lastMac = macAddress;
    await _prefs?.setString(_lastPrinterMacKey, macAddress);
    return printer;
  }

  /// Connects to a [Printer] object directly.
  Future<void> connectPrinter(Printer printer) async {
    final connected = await FlutterThermalPrinter.instance.connect(printer);
    if (!connected) {
      throw PrinterException(PrinterError.connectionFailed);
    }

    _connectedPrinter = printer.copyWith(isConnected: true);
    _lastMac = printer.address;
    await _prefs?.setString(_lastPrinterMacKey, printer.address!);
  }

  /// Connects to the last-used printer from SharedPreferences.
  ///
  /// Returns true if reconnected successfully, false if no last printer
  /// was saved or connection failed.
  Future<bool> reconnectLastPrinter() async {
    if (_lastMac == null) return false;

    try {
      // Ensure we have an up-to-date device list
      await startScan();
      await Future.delayed(const Duration(seconds: 3));
      await stopScan();

      await connect(_lastMac!);
      return true;
    } catch (_) {
      // Auto-reconnect failed — caller should show picker
      return false;
    }
  }

  /// Disconnects from the currently connected printer.
  Future<void> disconnect() async {
    if (_connectedPrinter == null) return;

    try {
      await FlutterThermalPrinter.instance.disconnect(_connectedPrinter!);
    } finally {
      _connectedPrinter = null;
    }
  }

  /// Sends a receipt PNG image to the connected printer.
  ///
  /// The [imageBytes] should be a PNG image sized for 80mm thermal paper
  /// (typically 576px wide at 203 DPI).
  ///
  /// Throws [PrinterException] if not connected or printing fails.
  Future<void> printImage(Uint8List imageBytes) async {
    if (_connectedPrinter == null) {
      throw PrinterException(PrinterError.connectionLost);
    }

    try {
      // Decode PNG to image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw PrinterException(PrinterError.printFailed);
      }

      // Ensure width is divisible by 8 (printer requirement)
      final width = _makeDivisibleBy8(image.width);
      final resized = img.copyResize(image, width: width);

      // Convert to grayscale for thermal printer
      final grayscale = img.grayscale(resized);

      // Generate ESC/POS raster data
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      final rasterBytes = generator.imageRaster(grayscale);

      // Send to printer
      await FlutterThermalPrinter.instance.printData(
        _connectedPrinter!,
        rasterBytes,
        longData: true,
      );
    } catch (e) {
      if (e is PrinterException) rethrow;
      throw PrinterException(PrinterError.printFailed, cause: e);
    }
  }

  /// Clears the last-used printer from storage.
  Future<void> clearLastPrinter() async {
    _lastMac = null;
    await _prefs?.remove(_lastPrinterMacKey);
  }

  /// Disposes of resources. Call when done with the service.
  Future<void> dispose() async {
    await stopScan();
    await disconnect();
  }

  /// Helper to get printers list with a timeout.
  Future<List<Printer>> _getPrintersWithTimeout({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<List<Printer>>();

    Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete([]);
      }
    });

    final subscription = FlutterThermalPrinter.instance.devicesStream.listen(
      (printers) {
        if (!completer.isCompleted) {
          completer.complete(printers);
        }
      },
    );

    await FlutterThermalPrinter.instance.getPrinters(
      connectionTypes: const [ConnectionType.BLE],
      androidUsesFineLocation: true,
    );

    final result = await completer.future;
    subscription.cancel();
    return result;
  }

  /// Make number divisible by 8 for printer compatibility.
  int _makeDivisibleBy8(int number) {
    if (number % 8 == 0) return number;
    return number + (8 - (number % 8));
  }
}

/// Exception thrown when a printer operation fails.
class PrinterException implements Exception {
  final PrinterError error;
  final Object? cause;

  PrinterException(this.error, {this.cause});

  @override
  String toString() => 'PrinterException($error, $cause)';
}

/// Provider for [PrinterService].
final printerServiceProvider = Provider<PrinterService>((ref) {
  return PrinterService();
});
