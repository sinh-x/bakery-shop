import '../../data/api/expense_category_service.dart';
import '../../data/models/expense_category.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bakery_app/shared/labels/accounting.dart';

/// Hardcoded fallback list of parent expense category names (FR6 backward
/// compat). Used when the API tree is unavailable so existing screens keep
/// working. Phase 4 wires the form/filter UI to the API-loaded tree via
/// [expenseCategoriesProvider].
const expenseCategories = <String>[
  VN.expenseCategoryIngredient,
  VN.expenseCategoryPackaging,
  VN.expenseCategoryDelivery,
  VN.expenseCategoryUtilities,
  VN.expenseCategoryTools,
  VN.expenseCategoryRepair,
  VN.expenseCategorySalaryAllowance,
  VN.expenseCategoryOther,
];

const expensePaymentMethods = <String>[
  VN.methodCash,
  VN.methodTransfer,
  VN.methodDebt,
];

const expensePaymentSources = <String>[
  VN.paymentSourceShopCash,
  VN.paymentSourcePhuongVCB,
  VN.paymentSourceAnVCB,
  VN.paymentSourceStaffAdvance,
];

/// Hardcoded fallback subcategory names grouped by parent category (FR6
/// backward compat). Mirrors the seed data from Phase 1. Phase 4 uses the
/// API-loaded tree as the primary source; this map is a fallback only.
const expenseSubcategoriesByParent = <String, List<String>>{
  VN.expenseCategoryIngredient: [
    VN.expenseSubcategoryEggs,
    VN.expenseSubcategoryCream,
    VN.expenseSubcategoryFlour,
    VN.expenseSubcategoryOtherAdditives,
  ],
  VN.expenseCategoryPackaging: [
    VN.expenseSubcategoryBoxAndBase,
    VN.expenseSubcategoryAccessories,
    VN.expenseSubcategoryWrap,
  ],
};

/// Placeholder label shown for expenses without a subcategory (FR6 / AC5).
const expenseSubcategoryNoneLabel = VN.expenseSubcategoryNone;

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
    VN.expenseCategoryIngredient: '5100',
    VN.expenseCategoryPackaging: '5200',
    VN.expenseCategoryDelivery: '5300',
    VN.expenseCategoryUtilities: '5400',
    VN.expenseCategoryTools: '5500',
    VN.expenseCategoryRepair: '5600',
    VN.expenseCategorySalaryAllowance: '5700',
    VN.expenseCategoryOther: '5800',
    VN.expenseSubcategoryEggs: '5110',
    VN.expenseSubcategoryCream: '5120',
    VN.expenseSubcategoryFlour: '5130',
    VN.expenseSubcategoryOtherAdditives: '5140',
    VN.expenseSubcategoryBoxAndBase: '5210',
    VN.expenseSubcategoryAccessories: '5220',
    VN.expenseSubcategoryWrap: '5230',
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