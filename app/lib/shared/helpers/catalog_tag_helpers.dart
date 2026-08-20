import 'package:bakery_app/shared/labels/products.dart';
/// Shared helper to get the display label for a tag category.
String getCategoryLabel(String category) {
  switch (category) {
    case ProductsLabels.tagCategoriesDoiTuong:
      return ProductsLabels.doiTuong;
    case ProductsLabels.tagCategoriesDip:
      return ProductsLabels.dip;
    case ProductsLabels.tagCategoriesPhongCach:
      return ProductsLabels.phongCach;
    default:
      return category;
  }
}
