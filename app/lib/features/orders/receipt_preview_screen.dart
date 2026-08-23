import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api/receipt_service.dart';
import '../../shared/providers/logged_by_provider.dart';
import '../../providers/order_providers.dart';
import 'providers/receipt_preview_notifier.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/shared.dart';
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
        ref.read(receiptPreviewProvider.notifier).setImage(bytes);
      }
    } catch (e) {
      if (mounted) {
        ref.read(receiptPreviewProvider.notifier).setError(e.toString());
      }
    }
  }

  Future<void> _shareImage() async {
    final imageBytes = ref.read(receiptPreviewProvider).imageBytes;
    if (imageBytes == null) return;
    try {
      final fileName =
          'receipt_${widget.orderRef}_${widget.receiptType.value}.png';

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(imageBytes, mimeType: 'image/png', name: fileName),
          ],
          text: '${widget.receiptType.label} - ${widget.orderRef}',
        ),
      );
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    }
  }

  Future<void> _saveImage() async {
    final imageBytes = ref.read(receiptPreviewProvider).imageBytes;
    if (imageBytes == null) return;
    try {
      final fileName =
          'receipt_${widget.orderRef}_${widget.receiptType.value}_${DateTime.now().millisecondsSinceEpoch}.png';
      await platform.saveToFile(imageBytes, fileName);
      if (mounted) {
        showTopSnackBar(context, SharedLabels.receiptSaved);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    }
  }

  Future<void> _printReceipt() async {
    // Check if Flow B applies: workTicket type and order is new
    final orderAsync = ref.read(orderDetailProvider(widget.orderRef));
    final isFlowB =
        widget.receiptType == ReceiptType.workTicket &&
        orderAsync.value?.status == 'new';

    final previewNotifier = ref.read(receiptPreviewProvider.notifier);
    final receiptService = ref.read(receiptServiceProvider);
    final printedBy = ref.read(loggedByProvider);
    final orderDetail = ref.read(orderDetailProvider(widget.orderRef).notifier);
    previewNotifier.setPrinting(true);
    try {
      // Always use server-side print API (USB thermal printer)
      await receiptService.printReceipt(
        orderRef: widget.orderRef,
        type: widget.receiptType,
        itemId: widget.itemId,
        printedBy: printedBy,
      );
      if (!mounted) return;
      showTopSnackBar(context, SharedLabels.printSuccess);

      // Flow B: auto-confirm order after successful work ticket print
      if (isFlowB) {
        await orderDetail.transitionTo('confirmed');
        if (mounted) {
          showTopSnackBar(context, SharedLabels.orderAutoConfirmed);
        }
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      previewNotifier.setPrinting(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiptPreviewProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiptType.label),
        actions: const [AppBarOverflowMenu()],
      ),
      body: _buildBody(state),
      bottomNavigationBar: state.imageBytes != null ? _buildActions(state) : null,
    );
  }

  Widget _buildBody(ReceiptPreviewState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(SharedLabels.apiError),
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                ref.read(receiptPreviewProvider.notifier).retry();
                _fetchReceipt();
              },
              child: const Text(SharedLabels.retry),
            ),
          ],
        ),
      );
    }

    if (state.imageBytes == null) {
      return const Center(child: Text(SharedLabels.errorLoading));
    }

    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 3.0,
        child: Image.memory(
          state.imageBytes!,
          fit: BoxFit.contain,
          width: double.infinity,
        ),
      ),
    );
  }

  Widget _buildActions(ReceiptPreviewState state) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saveImage,
                icon: const Icon(Icons.save_alt),
                label: const Text(SharedLabels.saveToGallery),
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
                onPressed: state.printing ? null : _printReceipt,
                icon: state.printing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.print),
                label: Text(state.printing ? 'Đang in...' : SharedLabels.print),
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
