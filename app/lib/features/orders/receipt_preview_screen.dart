import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api/receipt_service.dart';
import '../../providers/printer_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

class ReceiptPreviewScreen extends ConsumerStatefulWidget {
  const ReceiptPreviewScreen({
    super.key,
    required this.orderRef,
    required this.receiptType,
    this.itemId,
  });

  final String orderRef;
  final ReceiptType receiptType;
  final int? itemId;

  @override
  ConsumerState<ReceiptPreviewScreen> createState() =>
      _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends ConsumerState<ReceiptPreviewScreen> {
  Uint8List? _imageBytes;
  String? _error;
  bool _loading = true;

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
        type: widget.receiptType,
        itemId: widget.itemId,
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

  Future<void> _shareReceipt() async {
    if (_imageBytes == null) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'receipt_${widget.orderRef}_${widget.receiptType.value}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(_imageBytes!);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${widget.receiptType.label} - ${widget.orderRef}',
      );
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    }
  }

  Future<void> _saveToGallery() async {
    if (_imageBytes == null) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'receipt_${widget.orderRef}_${widget.receiptType.value}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(_imageBytes!);
      if (mounted) {
        showTopSnackBar(context, VN.receiptSaved);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    }
  }

  Future<void> _printReceipt() async {
    if (_imageBytes == null) return;

    final printerNotifier = ref.read(printerProvider.notifier);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(printerProvider);
          final status = state.value;

          // Auto-dismiss on success after a short delay
          if (status != null &&
              status.state == PrinterState.connected &&
              !status.isPrinting) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pop();
              showTopSnackBar(context, VN.printSuccess);
            });
          }

          return AlertDialog(
            content: Row(
              children: [
                if (status?.isPrinting == true ||
                    status?.state == PrinterState.printing)
                  const CircularProgressIndicator(strokeWidth: 2)
                else if (status?.state == PrinterState.connecting)
                  const CircularProgressIndicator(strokeWidth: 2)
                else if (status?.state == PrinterState.error)
                  const Icon(Icons.error_outline, color: Colors.red)
                else
                  const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    status?.isPrinting == true ||
                            status?.state == PrinterState.printing
                        ? VN.printing
                        : status?.state == PrinterState.connecting
                            ? VN.printerConnecting
                            : status?.state == PrinterState.error
                                ? (status?.errorMessage ?? VN.printFailed)
                                : VN.printing,
                  ),
                ),
              ],
            ),
            actions: [
              if (status?.state != PrinterState.printing &&
                  status?.isPrinting != true)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(VN.cancel),
                ),
            ],
          );
        },
      ),
    );

    // Attempt to print
    final success = await printerNotifier.printImage(_imageBytes!);

    if (!success && mounted) {
      Navigator.of(context).pop(); // Close the loading dialog
      final errorState = ref.read(printerProvider).value;
      if (errorState?.errorMessage != null) {
        showTopSnackBar(context, errorState!.errorMessage!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiptType.label),
      ),
      body: _buildBody(),
      bottomNavigationBar: _imageBytes != null ? _buildActions() : null,
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

  Widget _buildActions() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saveToGallery,
                icon: const Icon(Icons.save_alt),
                label: const Text(VN.saveToGallery),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _shareReceipt,
                icon: const Icon(Icons.share),
                label: const Text(VN.share),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _printReceipt,
                icon: const Icon(Icons.print),
                label: const Text(VN.print),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
