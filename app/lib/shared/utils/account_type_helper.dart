import 'package:flutter/material.dart';

import '../widgets/vietnamese_labels.dart';

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
      return VN.accountingTypeAsset;
    case 'liability':
      return VN.accountingTypeLiability;
    case 'equity':
      return VN.accountingTypeEquity;
    case 'income':
      return VN.accountingTypeIncome;
    case 'expense':
      return VN.accountingTypeExpense;
    default:
      return type;
  }
}