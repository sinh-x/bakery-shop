import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/receipt_service.dart';
import '../../shared/widgets/printer_picker_dialog.dart';
import '../../shared/widgets/vietnamese_labels.dart';

import '../orders/receipt_preview_print_stub.dart'
    if (dart.library.io) '../orders/receipt_preview_print_native.dart'
    if (dart.library.js_interop) '../orders/receipt_preview_print_web.dart'
    as platform;

/// POS receipt screen shown after order creation.
/// Displays receipt image with print and skip actions only.
class PosReceiptScreen extends ConsumerStatefulWidget {
  const PosReceiptScreen({super.key, required this.orderRef});

  final String orderRef;

  @override
  ConsumerState<PosReceiptScreen> createState() => _PosReceiptScreenState();
}

class _PosReceiptScreenState extends ConsumerState<PosReceiptScreen> {
  Uint8List? _imageBytes;
  String? _error;
  bool _loading = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _fetchReceipt();
  }

  Future<void> _fetchReceipt() async {
    try {
      final receiptService = ref.read(receiptServiceProvider);
      final bytes = await receiptService.fetchReceipt(
        orderRef: widget.orderRef,
        type: ReceiptType.customer,
      );
      if (mounted) {
        setState(() {
          _imageBytes = bytes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _printReceipt() async {
    setState(() => _printing = true);
    try {
      final receiptService = ref.read(receiptServiceProvider);

      if (kIsWeb) {
        await receiptService.printReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.customer,
        );
        if (!mounted) return;
        showTopSnackBar(context, VN.printSuccess);
      } else {
        if (_imageBytes == null) return;
        final printBytes = await receiptService.fetchReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.customer,
          photos: false,
        );

        if (!mounted) return;

        final result = await platform.tryPrintNative(context, printBytes, ref);

        if (!mounted) return;

        if (result == PrinterPickerResult.success) {
          showTopSnackBar(context, VN.printSuccess);
        } else if (result == PrinterPickerResult.failed) {
          showTopSnackBar(context, VN.printFailed);
        }
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _skip() {
    context.go('/pos');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biên nhận'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _skip,
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _skip,
                  icon: const Icon(Icons.check),
                  label: const Text('Xong'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _printing || _imageBytes == null ? null : _printReceipt,
                  icon: _printing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print),
                  label: Text(_printing ? 'Đang in...' : 'In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(VN.apiError),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _fetchReceipt();
              },
              child: const Text(VN.retry),
            ),
          ],
        ),
      );
    }

    if (_imageBytes == null) {
      return const Center(child: Text(VN.errorLoading));
    }

    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 3.0,
        child: Image.memory(
          _imageBytes!,
          fit: BoxFit.contain,
          width: double.infinity,
        ),
      ),
    );
  }
}
