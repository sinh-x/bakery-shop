import 'package:flutter/material.dart';

import '../../../data/providers/reconciliation_provider.dart';
import '../../../shared/labels/shared.dart';

Future<bool> showSubmitReviewDialog({
  required BuildContext context,
  required ReconciliationState state,
  required String staffName,
  required bool canSubmit,
}) async {
  final draft = state.draft;
  if (draft == null) {
    return false;
  }

  var totalSale = 0;
  var totalWaste = 0;
  for (final product in draft.products) {
    for (final option in product.options) {
      final optionKey = reconciliationOptionKey(
        product.productId,
        option.normalizedPrice,
      );
      final rows =
          state.saleRowsByOption[optionKey] ??
          const <ReconciliationSaleRowInput>[];
      totalSale += rows.fold<int>(0, (sum, row) => sum + row.quantity);
      totalWaste += state.wasteQtyByOption[optionKey] ?? 0;
    }
  }

  final issues = _collectUnresolvedIssues(state);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text(VN.xacNhanGuiDoiSoat),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${VN.nhanVien}: ${staffName.isEmpty ? VN.chuaChonNhanVien : staffName}',
            ),
            const SizedBox(height: 4),
            Text('${VN.tongSoLuongBan}: $totalSale'),
            Text('${VN.tongSoLuongHaoHut}: $totalWaste'),
            const SizedBox(height: 8),
            Text(
              VN.vanDeCanXuLyTruocKhiGui,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (issues.isEmpty)
              Text(
                VN.daSanSangGuiDoiSoat,
                style: TextStyle(color: Colors.green[700]),
              )
            else
              ...issues.map(
                (issue) => Text(
                  '- $issue',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (!canSubmit)
              Text(
                VN.daTatGuiDoiSoatKhiCoLoi,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(VN.huy),
          ),
          FilledButton(
            onPressed: canSubmit ? () => Navigator.of(context).pop(true) : null,
            child: const Text(VN.guiDoiSoat),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

List<String> _collectUnresolvedIssues(ReconciliationState state) {
  final draft = state.draft;
  if (draft == null) {
    return <String>[];
  }

  final optionNameByKey = <String, String>{};
  for (final product in draft.products) {
    for (final option in product.options) {
      final key = reconciliationOptionKey(product.productId, option.normalizedPrice);
      optionNameByKey[key] = '${product.name} - Gia ${option.normalizedPrice}';
    }
  }

  final issues = <String>[];
  for (final entry in state.optionErrors.entries) {
    final optionLabel = optionNameByKey[entry.key] ?? entry.key;
    issues.add('$optionLabel: ${entry.value}');
  }

  for (final entry in state.saleRowErrorsByOption.entries) {
    final optionLabel = optionNameByKey[entry.key] ?? entry.key;
    for (var index = 0; index < entry.value.length; index += 1) {
      final rowError = entry.value[index];
      final parts = <String>[
        if (rowError.quantity != null) rowError.quantity!,
        if (rowError.unitPrice != null) rowError.unitPrice!,
        if (rowError.paymentMethod != null) rowError.paymentMethod!,
      ];
      if (parts.isNotEmpty) {
        issues.add('$optionLabel - ${VN.dongBan} ${index + 1}: ${parts.join(', ')}');
      }
    }
  }
  return issues;
}
