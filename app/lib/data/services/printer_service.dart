// ignore_for_file: prefer_const_declarations  // DG-138#todo: replace with per-line suppressions after const declaration audit
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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

/// Manages Bluetooth Classic thermal printer discovery, connection, and printing.
class PrinterService {
  static const String _lastPrinterMacKey = 'last_printer_mac';

  SharedPreferences? _prefs;
  String? _connectedMac;
  String? _lastMac;

  /// Initializes the service. Must be called before any other methods.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _lastMac = _prefs?.getString(_lastPrinterMacKey);
  }

  /// Returns the last-used printer MAC address, or null if none saved.
  String? get lastPrinterMac => _lastMac;

  /// Returns true if a printer is currently connected.
  bool get isConnected => _connectedMac != null;

  /// Checks if Bluetooth is available and enabled.
  Future<bool> isBluetoothEnabled() async {
    return await PrintBluetoothThermal.bluetoothEnabled;
  }

  /// Requests Bluetooth and location permissions required on Android 12+.
  /// Returns true if all required permissions are granted.
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();

    return statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );
  }

  /// Returns paired Bluetooth devices filtered to likely printers.
  ///
  /// Requests permissions first, then filters by known thermal printer
  /// name patterns. If no matches, returns all bonded devices as fallback.
  Future<List<DiscoveredPrinter>> getBondedDevices() async {
    final granted = await requestPermissions();
    if (!granted) {
      throw PrinterException(PrinterError.locationPermissionDenied);
    }

    final devices = await PrintBluetoothThermal.pairedBluetooths;
    final all = devices
        .map((d) => DiscoveredPrinter(
              name: d.name,
              address: d.macAdress,
            ))
        .toList();

    final printers = all.where((d) => _looksLikePrinter(d.name)).toList();
    return printers.isNotEmpty ? printers : all;
  }

  /// Heuristic: does this device name look like a thermal printer?
  static bool _looksLikePrinter(String name) {
    final lower = name.toLowerCase();
    const patterns = [
      'y41bt', 'flashlabel', 'printer', 'print', 'label',
      'pos', 'tsc', 'xprinter', 'xp-', 'gprinter', 'epson',
      'star', 'bixolon', 'munbyn', 'peripage', 'phomemo',
      'niimbot', 'zebra', 'brother', 'rongta', 'hprt',
    ];
    return patterns.any(lower.contains);
  }

  /// Connects to a printer by MAC address.
  ///
  /// After connecting, saves the MAC to SharedPreferences for auto-reconnect.
  /// Retries once on failure with a short delay.
  Future<void> connect(String macAddress) async {
    // Disconnect any existing connection first
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
    _connectedMac = null;

    // First attempt
    var connected =
        await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);

    // Retry once after a short delay if first attempt fails
    if (!connected) {
      await Future.delayed(const Duration(seconds: 2));
      connected =
          await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
    }

    if (!connected) {
      throw PrinterException(PrinterError.connectionFailed);
    }

    _connectedMac = macAddress;
    _lastMac = macAddress;
    await _prefs?.setString(_lastPrinterMacKey, macAddress);
  }

  /// Connects to the last-used printer from SharedPreferences.
  ///
  /// Returns true if reconnected successfully, false if no last printer
  /// was saved or connection failed.
  Future<bool> reconnectLastPrinter() async {
    if (_lastMac == null) return false;

    try {
      await connect(_lastMac!);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Disconnects from the currently connected printer.
  Future<void> disconnect() async {
    if (_connectedMac == null) return;
    await PrintBluetoothThermal.disconnect;
    _connectedMac = null;
  }

  /// Sends a receipt PNG image to the connected printer using TSPL commands.
  ///
  /// The Y41BT is a TSPL label printer. We convert the image to a 1-bit
  /// bitmap and send it via TSPL BITMAP command.
  ///
  /// Throws [PrinterException] if not connected or printing fails.
  Future<void> printImage(Uint8List imageBytes) async {
    if (_connectedMac == null) {
      throw PrinterException(PrinterError.connectionLost);
    }

    // Verify connection is still alive
    final stillConnected = await PrintBluetoothThermal.connectionStatus;
    if (!stillConnected) {
      _connectedMac = null;
      throw PrinterException(PrinterError.connectionLost);
    }

    try {
      // Decode PNG to image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw PrinterException(PrinterError.printFailed);
      }

      // 76mm paper at 203 DPI = 608 dots, but use 576 (72 bytes) for margin
      const printWidth = 576;
      final resized = img.copyResize(image, width: printWidth);
      final grayscale = img.grayscale(resized);

      final widthBytes = printWidth ~/ 8; // 72
      final height = grayscale.height;

      // Convert to 1-bit bitmap — threshold 128 (standard midpoint)
      // with DENSITY 8 in TSPL for bold output
      const threshold = 128;
      final bitmapData = Uint8List(widthBytes * height);
      var offset = 0;
      for (int y = 0; y < height; y++) {
        for (int xByte = 0; xByte < widthBytes; xByte++) {
          int byte = 0;
          for (int bit = 0; bit < 8; bit++) {
            final x = xByte * 8 + bit;
            final pixel = grayscale.getPixel(x, y);
            // TSPL: bit 1 = white (no print), bit 0 = black (print)
            if (pixel.r >= threshold) {
              byte |= (0x80 >> bit);
            }
          }
          bitmapData[offset++] = byte;
        }
      }

      // Label height in mm (203 DPI ≈ 8 dots/mm)
      final heightMm = (height / 8).ceil();

      void tspl(List<int> target, String cmd) {
        target.addAll(ascii.encode(cmd));
        target.addAll([0x0D, 0x0A]); // \r\n
      }

      // Build complete TSPL command as one List<int>
      // Plugin handles 16KB chunking internally via outputStream
      final commands = <int>[];
      tspl(commands, 'SIZE 76 mm,$heightMm mm');
      tspl(commands, 'GAP 3 mm,0 mm');
      tspl(commands, 'SPEED 3');
      tspl(commands, 'DENSITY 8');
      tspl(commands, 'DIRECTION 0,0');
      tspl(commands, 'CLS');
      commands.addAll(ascii.encode('BITMAP 0,0,$widthBytes,$height,0,'));
      // Must use List<int>, not Uint8List — plugin casts to java.util.List
      commands.addAll(List<int>.from(bitmapData));
      commands.addAll([0x0D, 0x0A]);
      tspl(commands, 'PRINT 1,1');

      final result = await PrintBluetoothThermal.writeBytes(commands);
      if (!result) {
        throw PrinterException(PrinterError.printFailed);
      }
    } catch (e) {
      if (e is PrinterException) rethrow;
      throw PrinterException(PrinterError.printFailed, cause: e);
    }
  }

  /// Prints a simple TSPL text test to verify protocol works.
  Future<void> printTest() async {
    if (_connectedMac == null) {
      throw PrinterException(PrinterError.connectionLost);
    }

    final commands = <int>[];
    void tspl(String cmd) {
      commands.addAll(ascii.encode(cmd));
      commands.addAll([0x0D, 0x0A]);
    }

    tspl('SIZE 76 mm,30 mm');
    tspl('GAP 3 mm,0 mm');
    tspl('SPEED 3');
    tspl('DENSITY 8');
    tspl('DIRECTION 0,0');
    tspl('CLS');
    tspl('TEXT 10,10,"4",0,1,1,"TIEM BANH DOAN GIA"');
    tspl('TEXT 10,60,"3",0,1,1,"Test print - Bluetooth OK"');
    tspl('TEXT 10,100,"2",0,1,1,"Y41BT TSPL Protocol"');
    tspl('PRINT 1,1');

    await PrintBluetoothThermal.writeBytes(commands);
  }

  /// Clears the last-used printer from storage.
  Future<void> clearLastPrinter() async {
    _lastMac = null;
    await _prefs?.remove(_lastPrinterMacKey);
  }

  /// Disposes of resources. Call when done with the service.
  Future<void> dispose() async {
    await disconnect();
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
