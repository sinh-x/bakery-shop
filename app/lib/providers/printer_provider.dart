import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/printer_service.dart';

/// Printer connection state.
enum PrinterState {
  disconnected,
  connecting,
  connected,
  printing,
  error,
}

/// State for the printer notifier.
class PrinterStatus {
  final PrinterState state;
  final String? errorMessage;
  final bool isPrinting;

  const PrinterStatus({
    required this.state,
    this.errorMessage,
    this.isPrinting = false,
  });

  PrinterStatus copyWith({
    PrinterState? state,
    String? errorMessage,
    bool? isPrinting,
  }) {
    return PrinterStatus(
      state: state ?? this.state,
      errorMessage: errorMessage,
      isPrinting: isPrinting ?? this.isPrinting,
    );
  }

  static const disconnected = PrinterStatus(state: PrinterState.disconnected);
  static const connecting = PrinterStatus(state: PrinterState.connecting);
  static const connected = PrinterStatus(state: PrinterState.connected);
  static const printing = PrinterStatus(
    state: PrinterState.printing,
    isPrinting: true,
  );
}

/// Notifier that manages printer connection state and printing operations.
class PrinterNotifier extends AsyncNotifier<PrinterStatus> {
  late PrinterService _printerService;
  bool _serviceInitialized = false;

  @override
  Future<PrinterStatus> build() async {
    _printerService = ref.read(printerServiceProvider);
    if (!_serviceInitialized) {
      await _printerService.init();
      _serviceInitialized = true;
    }

    // Check if already connected
    if (_printerService.isConnected) {
      return PrinterStatus.connected;
    }

    // Try auto-reconnect if we have a saved MAC
    final lastMac = _printerService.lastPrinterMac;
    if (lastMac != null) {
      state = const AsyncValue.data(PrinterStatus.connecting);
      final success = await _printerService.reconnectLastPrinter();
      if (success) {
        return PrinterStatus.connected;
      }
    }

    return PrinterStatus.disconnected;
  }

  /// Attempts to print an image.
  ///
  /// Returns true if printing succeeded.
  /// Returns false and shows error message if printing failed.
  Future<bool> printImage(Uint8List imageBytes) async {
    final currentState = state.value;
    if (currentState == null) return false;

    // If not connected, show message that printer needs to be set up
    if (currentState.state == PrinterState.disconnected) {
      state = AsyncValue.data( // ignore: prefer_const_constructors
        const PrinterStatus(
          state: PrinterState.error,
          errorMessage: 'Máy in chưa kết nối. Vui lòng kết nối máy in trong Cài đặt.',
        ),
      );
      // Reset to disconnected after showing error
      await Future.delayed(const Duration(seconds: 3));
      state = const AsyncValue.data(PrinterStatus.disconnected);
      return false;
    }

    // If already printing, don't start another print
    if (currentState.isPrinting ||
        currentState.state == PrinterState.printing) {
      return false;
    }

    // Update to printing state
    state = const AsyncValue.data(PrinterStatus.printing);

    try {
      await _printerService.printImage(imageBytes);
      state = const AsyncValue.data(PrinterStatus.connected);
      return true;
    } on PrinterException catch (e) {
      state = AsyncValue.data(
        PrinterStatus(
          state: PrinterState.error,
          errorMessage: printerErrorMessage(e.error),
        ),
      );
      // Reset to connected state after showing error (printer may still be connected)
      await Future.delayed(const Duration(seconds: 3));
      if (_printerService.isConnected) {
        state = const AsyncValue.data(PrinterStatus.connected);
      } else {
        state = const AsyncValue.data(PrinterStatus.disconnected);
      }
      return false;
    } catch (e) {
      state = AsyncValue.data(
        PrinterStatus(
          state: PrinterState.error,
          errorMessage: 'Đã xảy ra lỗi khi in: $e',
        ),
      );
      await Future.delayed(const Duration(seconds: 3));
      if (_printerService.isConnected) {
        state = const AsyncValue.data(PrinterStatus.connected);
      } else {
        state = const AsyncValue.data(PrinterStatus.disconnected);
      }
      return false;
    }
  }

  /// Checks the current printer connection status.
  Future<PrinterStatus> checkConnection() async {
    if (!_printerService.isConnected) {
      return PrinterStatus.disconnected;
    }
    return PrinterStatus.connected;
  }
}

/// Provider for printer state management.
final printerProvider =
    AsyncNotifierProvider<PrinterNotifier, PrinterStatus>(PrinterNotifier.new);
