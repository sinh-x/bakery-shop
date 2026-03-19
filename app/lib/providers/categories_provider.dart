import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/category_service.dart';
import '../data/models/category.dart';

class CategoriesNotifier extends AsyncNotifier<List<Category>> {
  @override
  Future<List<Category>> build() async {
    return _fetch();
  }

  Future<List<Category>> _fetch() {
    final service = ref.read(categoryServiceProvider);
    return service.listCategories(includeInactive: true);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<Category> createCategory({
    required String name,
    required String slug,
    required String codePrefix,
    String icon = '',
  }) async {
    final service = ref.read(categoryServiceProvider);
    final category = await service.createCategory(
      name: name,
      slug: slug,
      codePrefix: codePrefix,
      icon: icon,
    );
    await refresh();
    return category;
  }

  Future<Category> updateCategory(
    int id, {
    String? name,
    String? codePrefix,
    int? active,
    String? icon,
  }) async {
    final service = ref.read(categoryServiceProvider);
    final category = await service.updateCategory(
      id,
      name: name,
      codePrefix: codePrefix,
      active: active,
      icon: icon,
    );
    await refresh();
    return category;
  }

  Future<void> deactivateCategory(int id) async {
    await updateCategory(id, active: 0);
  }

  Future<void> reactivateCategory(int id) async {
    await updateCategory(id, active: 1);
  }

  Future<void> reorderCategories(List<int> ids) async {
    final service = ref.read(categoryServiceProvider);
    await service.reorderCategories(ids);
    await refresh();
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<Category>>(
        CategoriesNotifier.new);
