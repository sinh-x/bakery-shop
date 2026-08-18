import '../../data/api/expense_category_service.dart';
import '../../data/models/expense_category.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/labels/orders.dart';
/// Hardcoded fallback list of parent expense category names (FR6 backward
/// compat). Used when the API tree is unavailable so existing screens keep
/// working. Phase 4 wires the form/filter UI to the API-loaded tree via
/// [expenseCategoriesProvider].
const expenseCategories = <String>[
  ExpensesLabels.expenseCategoryIngredient,
  ExpensesLabels.expenseCategoryPackaging,
  ExpensesLabels.expenseCategoryDelivery,
  ExpensesLabels.expenseCategoryUtilities,
  ExpensesLabels.expenseCategoryTools,
  ExpensesLabels.expenseCategoryRepair,
  ExpensesLabels.expenseCategorySalaryAllowance,
  ExpensesLabels.expenseCategoryOther,
];

const expensePaymentMethods = <String>[
  OrdersLabels.methodCash,
  OrdersLabels.methodTransfer,
  OrdersLabels.methodDebt,
];

const expensePaymentSources = <String>[
  ExpensesLabels.paymentSourceDrawerCash,
  ExpensesLabels.paymentSourceOwnerCash,
  ExpensesLabels.paymentSourcePhuongVCB,
  ExpensesLabels.paymentSourceAnVCB,
  ExpensesLabels.paymentSourceStaffAdvance,
];

/// Hardcoded fallback subcategory names grouped by parent category (FR6
/// backward compat). Mirrors the seed data from Phase 1. Phase 4 uses the
/// API-loaded tree as the primary source; this map is a fallback only.
const expenseSubcategoriesByParent = <String, List<String>>{
  ExpensesLabels.expenseCategoryIngredient: [
    ExpensesLabels.expenseSubcategoryEggs,
    ExpensesLabels.expenseSubcategoryCream,
    ExpensesLabels.expenseSubcategoryFlour,
    ExpensesLabels.expenseSubcategoryOtherAdditives,
    ExpensesLabels.expenseSubcategoryFruits,
  ],
  ExpensesLabels.expenseCategoryPackaging: [
    ExpensesLabels.expenseSubcategoryBoxAndBase,
    ExpensesLabels.expenseSubcategoryAccessories,
    ExpensesLabels.expenseSubcategoryWrap,
  ],
};

/// Placeholder label shown for expenses without a subcategory (FR6 / AC5).
const expenseSubcategoryNoneLabel = ExpensesLabels.expenseSubcategoryNone;

/// Riverpod provider that loads the expense category tree from
/// ``GET /api/expense-categories`` (FR5). Falls back to a synthetic tree
/// built from [expenseCategories] and [expenseSubcategoriesByParent] when the
/// API call fails — preserving FR6 backward compatibility.
final expenseCategoriesProvider =
    FutureProvider<List<ExpenseCategory>>((ref) async {
  final service = ref.watch(expenseCategoryServiceProvider);
  try {
    return await service.listCategories();
  } catch (_) {
    return _fallbackTree();
  }
});

/// Builds a fallback category tree from the hardcoded constants (used when
/// the API is unreachable). Account codes mirror the Phase 1 seed data.
List<ExpenseCategory> _fallbackTree() {
  const accountCodes = <String, String>{
    ExpensesLabels.expenseCategoryIngredient: '5100',
    ExpensesLabels.expenseCategoryPackaging: '5200',
    ExpensesLabels.expenseCategoryDelivery: '5300',
    ExpensesLabels.expenseCategoryUtilities: '5400',
    ExpensesLabels.expenseCategoryTools: '5500',
    ExpensesLabels.expenseCategoryRepair: '5600',
    ExpensesLabels.expenseCategorySalaryAllowance: '5700',
    ExpensesLabels.expenseCategoryOther: '5800',
    ExpensesLabels.expenseSubcategoryEggs: '5110',
    ExpensesLabels.expenseSubcategoryCream: '5120',
    ExpensesLabels.expenseSubcategoryFlour: '5130',
    ExpensesLabels.expenseSubcategoryOtherAdditives: '5140',
    ExpensesLabels.expenseSubcategoryFruits: '5150',
    ExpensesLabels.expenseSubcategoryBoxAndBase: '5210',
    ExpensesLabels.expenseSubcategoryAccessories: '5220',
    ExpensesLabels.expenseSubcategoryWrap: '5230',
  };
  var nextId = 1;
  final tree = <ExpenseCategory>[];
  for (final parentName in expenseCategories) {
    final parentId = nextId++;
    final children = <ExpenseCategory>[];
    for (final childName
        in expenseSubcategoriesByParent[parentName] ?? const <String>[]) {
      children.add(ExpenseCategory(
        id: nextId++,
        name: childName,
        accountCode: accountCodes[childName] ?? '',
        parentId: parentId,
      ));
    }
    tree.add(ExpenseCategory(
      id: parentId,
      name: parentName,
      accountCode: accountCodes[parentName] ?? '',
      parentId: null,
      children: children,
    ));
  }
  return tree;
}