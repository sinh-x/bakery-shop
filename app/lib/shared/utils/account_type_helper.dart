import 'package:flutter/material.dart';
import 'package:bakery_app/shared/labels/accounting.dart';
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
      return AccountingLabels.accountingTypeAsset;
    case 'liability':
      return AccountingLabels.accountingTypeLiability;
    case 'equity':
      return AccountingLabels.accountingTypeEquity;
    case 'income':
      return AccountingLabels.accountingTypeIncome;
    case 'expense':
      return AccountingLabels.accountingTypeExpense;
    default:
      return type;
  }
}