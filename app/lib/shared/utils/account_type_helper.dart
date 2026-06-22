import 'package:flutter/material.dart';

/// Shared helpers for accounting account-type presentation.
///
/// Extracted from accounts_tab.dart and balances_tab.dart to avoid
/// duplicated `_typeColor`/`_typeLabel` switch blocks (DG-175 review cycle 1,
/// finding CQ-2).

Color accountTypeColor(String type) {
  switch (type) {
    case 'asset':
      return Colors.blue;
    case 'liability':
      return Colors.orange;
    case 'equity':
      return Colors.purple;
    case 'income':
      return Colors.green;
    case 'expense':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

String accountTypeLabel(String type) {
  switch (type) {
    case 'asset':
      return 'Tài sản';
    case 'liability':
      return 'Nợ phải trả';
    case 'equity':
      return 'Vốn chủ sở hữu';
    case 'income':
      return 'Doanh thu';
    case 'expense':
      return 'Chi phí';
    default:
      return type;
  }
}