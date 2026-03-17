import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/category_service.dart';
import '../data/models/category.dart';

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final service = ref.watch(categoryServiceProvider);
  return service.listCategories();
});
