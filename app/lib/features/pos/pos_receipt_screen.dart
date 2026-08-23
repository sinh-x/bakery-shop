import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api/receipt_service.dart';
import '../../shared/providers/logged_by_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'providers/pos_receipt_notifier.dart';
import '../../providers/form_draft_session_notifier.dart';
/// POS receipt screen shown after order creation.
/// Displays receipt image with print and skip actions only.
class PosReceiptScreen extends ConsumerStatefulWidget {
  const PosReceiptScreen({super.key, required this.orderRef});

  final String orderRef;

  @override
  ConsumerState<PosReceiptScreen> createState() => _PosReceiptScreenState();
}

class _PosReceiptScreenState extends ConsumerState<PosReceiptScreen> {
  @override
  void initState() {
    super.initState();
    _fetchReceipt();
  }

  Future<void> _fetchReceipt() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final epoch = container.read(formDraftSessionEpochProvider);
    final receiptService = container.read(receiptServiceProvider);
    final receiptNotifier = container.read(posReceiptProvider.notifier);
    final orderRef = widget.orderRef;
    try {
      final bytes = await receiptService.fetchReceipt(
        orderRef: orderRef,
        type: ReceiptType.customer,
      );
      if (container.read(formDraftSessionEpochProvider) == epoch) {
        receiptNotifier.setLoaded(bytes);
      }
    } catch (e) {
      if (container.read(formDraftSessionEpochProvider) == epoch) {
        receiptNotifier.setError(e.toString());
      }
    }
  }

  Future<void> _printReceipt() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final receiptNotifier = container.read(posReceiptProvider.notifier);
    final generation = receiptNotifier.startPrinting();
    final receiptService = container.read(receiptServiceProvider);
    final printedBy = container.read(loggedByProvider);
    final orderRef = widget.orderRef;
    try {
      // Always use server-side print API (USB thermal printer)
      await receiptService.printReceipt(
        orderRef: orderRef,
        type: ReceiptType.customer,
        printedBy: printedBy,
      );
      if (!mounted) return;
      showTopSnackBar(context, SharedLabels.printSuccess);
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      receiptNotifier.stopPrintingIfCurrent(generation);
    }
  }

  void _skip() {
    context.go('/pos');
  }

  Future<void> _shareImage() async {
    final imageBytes = ref.read(posReceiptProvider).imageBytes;
    if (imageBytes == null) return;
    try {
      const fileName = 'receipt_customer.png';

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(imageBytes, mimeType: 'image/png', name: fileName),
          ],
          text: '${ReceiptType.customer.label} - ${widget.orderRef}',
        ),
      );
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    }
  }

  @override
  // ignore: prefer_const_constructors
  Widget build(BuildContext context) {
    final receiptState = ref.watch(posReceiptProvider);
    final imageBytes = receiptState.imageBytes;
    final printing = receiptState.printing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biên nhận'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _skip),
        actions: const [AppBarOverflowMenu()],
      ),
      body: _buildBody(receiptState),
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
                child: OutlinedButton.icon(
                  onPressed: imageBytes == null ? null : _shareImage,
                  icon: const Icon(Icons.share),
                  label: const Text(SharedLabels.share),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: printing || imageBytes == null
                      ? null
                      : _printReceipt,
                  icon: printing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print),
                  label: Text(printing ? 'Đang in...' : 'In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(PosReceiptState receiptState) {
    if (receiptState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (receiptState.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(SharedLabels.apiError),
            const SizedBox(height: 8),
            Text(
              receiptState.error!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                ref.read(posReceiptProvider.notifier).resetForRetry();
                _fetchReceipt();
              },
              child: const Text(SharedLabels.retry),
            ),
          ],
        ),
      );
    }

    if (receiptState.imageBytes == null) {
      return const Center(child: Text(SharedLabels.errorLoading));
    }

    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 3.0,
        child: Image.memory(
          receiptState.imageBytes!,
          fit: BoxFit.contain,
          width: double.infinity,
        ),
      ),
    );
  }
}
