import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense_category.dart';
import 'api_client.dart';

/// Loads the expense category tree from ``GET /api/expense-categories``
/// (DG-302 Phase 3, FR5). The tree is seeded server-side and used to
/// populate category/subcategory dropdowns in the expense form (Phase 4).
class ExpenseCategoryService {
  final Dio _dio;

  ExpenseCategoryService(this._dio);

  Future<List<ExpenseCategory>> listCategories() async {
    final response = await _dio.get('/api/expense-categories');
    final list = response.data as List;
    return list
        .map((json) => ExpenseCategory.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final expenseCategoryServiceProvider =
    Provider<ExpenseCategoryService>((ref) {
  final dio = ref.watch(dioProvider);
  return ExpenseCategoryService(dio);
});