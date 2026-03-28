import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api/receipt_service.dart';
import '../../shared/widgets/vietnamese_labels.dart';

import 'receipt_preview_print_stub.dart'
    if (dart.library.io) 'receipt_preview_print_native.dart'
    if (dart.library.js_interop) 'receipt_preview_print_web.dart'
    as platform;

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

  Future<void> _shareImage() async {
    if (_imageBytes == null) return;
    try {
      final fileName =
          'receipt_${widget.orderRef}_${widget.receiptType.value}.png';

      // Save to temp file then share
      await platform.saveToFile(_imageBytes!, fileName);

      await Share.shareXFiles(
        [XFile.fromData(_imageBytes!, mimeType: 'image/png', name: fileName)],
        text: '${widget.receiptType.label} - ${widget.orderRef}',
      );
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    }
  }

  Future<void> _saveImage() async {
    if (_imageBytes == null) return;
    try {
      final fileName =
          'receipt_${widget.orderRef}_${widget.receiptType.value}_${DateTime.now().millisecondsSinceEpoch}.png';
      await platform.saveToFile(_imageBytes!, fileName);
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

    setState(() => _printing = true);
    try {
      // Fetch a no-photos version for printing
      final receiptService = ref.read(receiptServiceProvider);
      final printBytes = await receiptService.fetchReceipt(
        orderRef: widget.orderRef,
        type: widget.receiptType,
        itemId: widget.itemId,
        photos: false,
      );

      if (!mounted) return;

      if (kIsWeb) {
        platform.printWeb(printBytes);
      } else {
        await platform.printNative(context, printBytes, ref);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _printing = false);
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
                onPressed: _saveImage,
                icon: const Icon(Icons.save_alt),
                label: const Text(VN.saveToGallery),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shareImage,
                icon: const Icon(Icons.share),
                label: const Text('Chia sẻ'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _printing ? null : _printReceipt,
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
                label: Text(_printing ? 'Đang in...' : VN.print),
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
