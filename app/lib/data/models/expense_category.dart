/// Expense category tree model (DG-302 Phase 3, FR5 / FR3 / FR6).
///
/// Mirrors the JSON returned by ``GET /api/expense-categories``: each parent
/// category carries a [children] list of subcategories. Subcategories have a
/// non-null [parentId] and an empty [children] list. The model is read-only
/// (the backend seeds the tree), so a plain Dart class is used instead of
/// freezed codegen — matching the [Category] model pattern.
class ExpenseCategory {
  final int id;
  final String name;
  final String accountCode;
  final int? parentId;

  /// Subcategories nested under this category. Empty for leaf nodes.
  final List<ExpenseCategory> children;

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.accountCode,
    this.parentId,
    this.children = const <ExpenseCategory>[],
  });

  /// Whether this category is a parent (has subcategories).
  bool get hasChildren => children.isNotEmpty;

  /// Whether this category is a subcategory (has a parent).
  bool get isSubcategory => parentId != null;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final children = <ExpenseCategory>[];
    if (rawChildren is List) {
      for (final c in rawChildren) {
        if (c is Map<String, dynamic>) {
          children.add(ExpenseCategory.fromJson(c));
        }
      }
    }
    return ExpenseCategory(
      id: json['id'] as int,
      name: json['name'] as String,
      accountCode: json['account_code'] as String,
      parentId: json['parent_id'] as int?,
      children: children,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'account_code': accountCode,
        'parent_id': parentId,
        'children': children.map((c) => c.toJson()).toList(),
      };
}

/// Helper extensions for working with the loaded category tree.
extension ExpenseCategoryTree on List<ExpenseCategory> {
  /// Flatten the tree into a list of parent names (for backward-compatible
  /// dropdown population).
  List<String> get parentNames => map((c) => c.name).toList();

  /// Look up a parent category by name. Returns null when not found.
  ExpenseCategory? parentNamed(String name) {
    for (final c in this) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Look up the subcategories of [parentName]. Returns an empty list when
  /// the parent has no children or is not found (FR6 backward compat).
  List<ExpenseCategory> subcategoriesOf(String parentName) {
    final parent = parentNamed(parentName);
    return parent?.children ?? const <ExpenseCategory>[];
  }

  /// All subcategory names across the tree (for filter chips / labels).
  List<String> get allSubcategoryNames =>
      expand((c) => c.children).map((c) => c.name).toList();

  /// Find the parent name for a subcategory [name]. Returns null when [name]
  /// is not a subcategory or when the tree does not contain it.
  String? parentNameOfSubcategory(String name) {
    for (final parent in this) {
      for (final child in parent.children) {
        if (child.name == name) return parent.name;
      }
    }
    return null;
  }
}