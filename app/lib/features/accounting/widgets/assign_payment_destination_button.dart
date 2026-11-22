import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/payment_destination_provider.dart';
import '../../../shared/labels/accounting.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/utils.dart' show paymentTargetAccounts, showTopSnackBar;

/// Selection is an immediate confirmed action, not a retained form draft.
/// Busy/error state is isolated to the exact receipt and retained on dismissal.
class AssignPaymentDestinationButton extends ConsumerWidget {
  const AssignPaymentDestinationButton({
    super.key,
    required this.orderRef,
    required this.transactionId,
    this.onAssigned,
  });

  final String orderRef;
  final String transactionId;
  final VoidCallback? onAssigned;

  String _errorMessage(Object? error) {
    if (error is DioException && error.response?.data is Map) {
      return (error.response!.data as Map)['detail']?.toString() ??
          SharedLabels.apiError;
    }
    return SharedLabels.apiError;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = assignPaymentDestinationProvider((
      orderRef,
      transactionId,
    ));
    final operation = ref.watch(provider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          enabled: !operation.isLoading,
          tooltip: AccountingLabels.assignDestination,
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: '',
              child: Text(OrdersLabels.methodCash),
            ),
            for (final account in paymentTargetAccounts)
              PopupMenuItem(value: account, child: Text(account)),
          ],
          onSelected: (account) async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(
                  account.isEmpty ? OrdersLabels.methodCash : account,
                ),
                content: const Text(AccountingLabels.assignmentConfirm),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(SharedLabels.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(AccountingLabels.assignDestination),
                  ),
                ],
              ),
            );
            if (confirmed != true || !context.mounted) return;
            final success = await ref
                .read(provider.notifier)
                .assign(account.isEmpty ? 'cash' : 'transfer', account);
            if (success && context.mounted) {
              showTopSnackBar(context, AccountingLabels.destinationAssigned);
              onAssigned?.call();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: operation.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(AccountingLabels.assignDestination),
          ),
        ),
        if (operation.hasError)
          Text(
            _errorMessage(operation.error),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
