import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/product.dart';

final productsProvider = Provider<List<Product>>((ref) {
  return [];
});
