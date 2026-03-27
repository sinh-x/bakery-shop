import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api/receipt_service.dart';
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
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _shareReceipt,
                icon: const Icon(Icons.share),
                label: const Text(VN.share),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
